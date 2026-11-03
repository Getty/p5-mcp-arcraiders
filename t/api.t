#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use FindBin;

use lib "$FindBin::Bin/lib";
use ArcTest;
use FrozenClock;

use_ok('MCP::ArcRaiders');
use_ok('WWW::MetaForge::ArcRaiders');

# The offline suite never talks to the network: every request goes to the
# MockUA, which serves the byte-faithful live responses in t/fixtures.
my $json = ArcTest::json();
my $mcp  = ArcTest::mcp();

subtest 'Object creation' => sub {
  isa_ok($mcp, 'MCP::ArcRaiders');
  isa_ok($mcp->api, 'WWW::MetaForge::ArcRaiders');
  isa_ok($mcp->server, 'MCP::Server');
  is($mcp->server->name, 'arcraiders', 'server name is correct');
};

subtest 'search_items tool' => sub {
  my ($tool) = grep { $_->name eq 'search_items' } @{$mcp->server->tools};
  ok($tool, 'search_items tool exists');

  my $result = $tool->code->($tool, { search => 'Anvil', limit => 10 });
  ok($result, 'returns result');

  my $data = eval { $json->decode($result) };
  ok(!$@, 'result is valid JSON');
  ok(ref $data eq 'ARRAY', 'result is array');
  ok(@$data > 0, 'has items');

  my $item = $data->[0];
  ok($item->{name}, 'item has name');
  ok(exists $item->{item_type}, 'item has item_type');
  ok(exists $item->{value}, 'item has value');
  ok(exists $item->{stat_block}, 'item has stat_block');
  ok(!exists $item->{category}, 'old category field is gone');
};

subtest 'get_item_details tool' => sub {
  my ($tool) = grep { $_->name eq 'get_item_details' } @{$mcp->server->tools};
  ok($tool, 'get_item_details tool exists');

  my $result = $tool->code->($tool, { name => 'Adrenaline Shot' });
  ok($result, 'returns result');

  my $data = eval { $json->decode($result) };
  ok(!$@, 'result is valid JSON') or diag("Parse error: $@, result: $result");
  ok(ref $data eq 'ARRAY' && @$data, 'has items') or return;

  my ($item) = grep { $_->{name} eq 'Adrenaline Shot' } @$data;
  ok($item, 'found Adrenaline Shot') or return;
  ok(@{ $item->{components} } > 0, 'has crafting components');
  ok(exists $item->{recycle_components}, 'has recycle_components');
  is($item->{sold_by}[0]{trader_name}, 'Lance', 'sold_by names the trader');
  ok(exists $item->{workbench}, 'has workbench');
  ok(!exists $item->{crafting_requirements}, 'old crafting_requirements field is gone');
};

subtest 'get_item_details used_in' => sub {
  my ($tool) = grep { $_->name eq 'get_item_details' } @{$mcp->server->tools};
  my $data = eval { $json->decode($tool->code->($tool, { name => 'Advanced ARC Powercell' })) };
  ok(ref $data eq 'ARRAY' && @$data, 'has items') or return;

  my ($item) = grep { $_->{name} eq 'Advanced ARC Powercell' } @$data;
  ok($item, 'found item') or return;
  ok(@{ $item->{used_in} } > 0, 'used_in lists the crafted items');
  is_deeply([ sort keys %{ $item->{used_in}[0] } ], [qw(id name quantity)], 'used_in entry is id, name, quantity');
  is($item->{used_in}[0]{id}, 'energy-ammo', 'used_in names the crafted item');
};

subtest 'get_traders tool' => sub {
  my ($tool) = grep { $_->name eq 'get_traders' } @{$mcp->server->tools};
  ok($tool, 'get_traders tool exists');

  my $result = $tool->code->($tool, {});
  ok($result, 'returns result');

  my $data = eval { $json->decode($result) };
  ok(!$@, 'result is valid JSON');
  ok(ref $data eq 'ARRAY', 'result is array');
  ok(@$data > 0, 'has traders');

  my $trader = $data->[0];
  ok($trader->{name}, 'trader has name');
  ok(exists $trader->{inventory}, 'trader has inventory');
  ok(@{ $trader->{inventory} } > 0, 'inventory has items');
  ok(exists $trader->{inventory}[0]{trader_price}, 'inventory item has trader_price');
};

subtest 'get_event_timers tool' => sub {
  my ($tool) = grep { $_->name eq 'get_event_timers' } @{$mcp->server->tools};
  ok($tool, 'get_event_timers tool exists');

  my $result = FrozenClock::at('2026-11-03T08:30:00', sub { $tool->code->($tool, {}) });
  ok($result, 'returns result');

  my $data = eval { $json->decode($result) };
  ok(!$@, 'result is valid JSON');
  ok(ref $data eq 'ARRAY' && @$data, 'result is a list of events') or return;

  my ($event) = grep { $_->{name} eq 'Night Raid' && $_->{map} eq 'Spaceport' } @$data;
  ok($event, 'found Night Raid on Spaceport') or return;
  ok(ref $event->{times} eq 'ARRAY' && @{ $event->{times} } > 1, 'times is a list of slots');
  like($event->{times}[0]{start}, qr/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/, 'slot start is ISO 8601 UTC');
  is($event->{times}[2]{start}, '2026-11-03T08:00:00Z', 'slot start is the absolute time of the API');
  ok($event->{is_active_now}, 'is_active_now is true inside the slot');
  ok(exists $event->{icon}, 'has icon');
  ok(exists $event->{region}, 'has region');
};

subtest 'get_active_events tool' => sub {
  my ($tool) = grep { $_->name eq 'get_active_events' } @{$mcp->server->tools};
  ok($tool, 'get_active_events tool exists');

  my $data = FrozenClock::at('2026-11-03T08:30:00', sub { $json->decode($tool->code->($tool, {})) });
  ok(@$data > 0, 'events are active at 08:30');
  ok((!grep { !$_->{is_active_now} } @$data), 'all of them are active');
  ok((grep { $_->{name} eq 'Night Raid' } @$data), 'Night Raid is among them');

  my $none = FrozenClock::at('2026-11-04T23:59:00', sub { $tool->code->($tool, {}) });
  is($none, 'No events are currently active', 'a plain sentence when nothing runs');
};

subtest 'get_quests tool' => sub {
  my ($tool) = grep { $_->name eq 'get_quests' } @{$mcp->server->tools};
  ok($tool, 'get_quests tool exists');

  my $result = $tool->code->($tool, {});
  ok($result, 'returns result');

  my $data = eval { $json->decode($result) };
  ok(!$@, 'result is valid JSON');
  ok(ref $data eq 'ARRAY', 'result is array');
  is(scalar @$data, 123, 'all quests over all four pages');
  is(scalar(keys %{ { map { $_->{id} => 1 } @$data } }), 123, 'no quest twice');

  my $quest = $data->[0];
  ok($quest->{name}, 'quest has name');
  ok(exists $quest->{trader_name}, 'quest has trader_name');
  ok(exists $quest->{xp}, 'quest has xp');
  ok(ref $quest->{rewards} eq 'ARRAY', 'quest rewards is a list');
  ok(exists $quest->{description}, 'quest has description');
  ok(ref $quest->{additional_rewards} eq 'ARRAY', 'quest has additional_rewards');
  ok(ref $quest->{manifest} eq 'HASH' && exists $quest->{manifest}{prerequisites}, 'quest has the manifest');

  my $schema = ArcTest::tool($mcp, 'get_quests')->input_schema;
  ok(!exists $schema->{properties}{type}, 'the type filter is gone: the API has no quest type');
};

subtest 'get_arcs tool' => sub {
  my ($tool) = grep { $_->name eq 'get_arcs' } @{$mcp->server->tools};
  ok($tool, 'get_arcs tool exists');

  my $result = $tool->code->($tool, { include_loot => 1 });
  ok($result, 'returns result');

  my $data = eval { $json->decode($result) };
  ok(!$@, 'result is valid JSON');
  ok(ref $data eq 'ARRAY', 'result is array');

  if (@$data) {
    my $arc = $data->[0];
    ok($arc->{name}, 'arc has name');
    ok(exists $arc->{loot}, 'arc has loot');
    ok(ref $arc->{data} eq 'HASH', 'arc has data');
  }
};

subtest 'get_map_data tool' => sub {
  my ($tool) = grep { $_->name eq 'get_map_data' } @{$mcp->server->tools};
  ok($tool, 'get_map_data tool exists');

  my $result = $tool->code->($tool, { map => 'dam', category => 'arc', subcategory => 'bastion' });
  my $data = eval { $json->decode($result) };
  ok(!$@, 'result is valid JSON') or diag("Parse error: $@, result: $result");
  ok(ref $data eq 'ARRAY' && @$data, 'has markers') or return;

  my $marker = $data->[0];
  is($marker->{category}, 'arc', 'marker category');
  is($marker->{subcategory}, 'bastion', 'marker subcategory');
  ok(defined $marker->{x} && defined $marker->{y}, 'marker has coordinates');
  ok(exists $marker->{behind_locked_door}, 'marker has behind_locked_door');
  ok(exists $marker->{$_}, "marker has $_") for qw(community source_id route_id);
};

subtest 'get_map_data tool - Pendola Pass' => sub {
  my ($tool) = grep { $_->name eq 'get_map_data' } @{$mcp->server->tools};

  my @maps = @{ $tool->input_schema->{properties}{map}{enum} };
  is_deeply(\@maps, [ $mcp->api->maps ], 'the map enum is what the API object lists');
  ok((grep { $_ eq 'pendola-pass' } @maps), 'pendola-pass is selectable');
  ok($tool->input_schema->{properties}{map}{enum} && !$tool->validate_input({ map => 'pendola-pass', category => 'arc' }), 'the schema accepts pendola-pass');
  ok($tool->validate_input({ map => 'nowhere', category => 'arc' }), 'the schema refuses an unknown map');

  my $data = $json->decode($tool->code->($tool, { map => 'pendola-pass', category => 'locations' }));
  is(scalar @$data, 1, 'one location marker in the fixture');
  is($data->[0]{subcategory}, 'extraction', 'extraction point');
  is($data->[0]{name}, 'Reckless Transceiver', 'named marker');

  ok(!$tool->validate_input({ map => 'dam', category => $_ }), "category $_ is accepted") for qw(arc containers locations events nature quests);
  my $nature = $json->decode($tool->code->($tool, { map => 'pendola-pass', category => 'nature' }));
  is($nature->[0]{subcategory}, 'candleberries', 'a nature marker');
};

subtest 'list_maps tool' => sub {
  my ($tool) = grep { $_->name eq 'list_maps' } @{$mcp->server->tools};
  ok($tool, 'list_maps tool exists');

  my $result = $tool->code->($tool, {});
  ok($result, 'returns result');

  my $data = eval { $json->decode($result) };
  ok(!$@, 'result is valid JSON');
  ok(ref $data eq 'ARRAY', 'result is array');
  ok(@$data >= 7, 'has at least 7 maps');
  ok((grep { $_->{id} eq 'riven-tides' } @$data), 'contains riven-tides');
  ok((grep { $_->{id} eq 'pendola-pass' && $_->{name} eq 'Pendola Pass' } @$data), 'contains pendola-pass');

  my @names = map { $_->{name} } @$data;
  ok((grep { /Dam/ } @names), 'contains Dam');
};

subtest 'calculate_requirements tool - direct' => sub {
  my ($tool) = grep { $_->name eq 'calculate_requirements' } @{$mcp->server->tools};
  ok($tool, 'calculate_requirements tool exists');

  my $result = $tool->code->($tool, {
    items => [{ item => 'Agave Juice', count => 2 }],
    base_only => 0,
  });
  ok($result, 'returns result');

  my $data = eval { $json->decode($result) };
  ok(!$@, 'result is valid JSON') or diag("Error: $@");
  ok(ref $data eq 'HASH', 'result is hash');
  ok(exists $data->{requirements}, 'has requirements');
  ok(exists $data->{missing}, 'has missing');
  ok(ref $data->{requirements} eq 'ARRAY', 'requirements is array');
  ok(ref $data->{missing} eq 'ARRAY', 'missing is array');

  # The fixture holds page 1 of the items: Agave is on it, the other component is not
  my ($agave) = grep { $_->{item} eq 'Agave' } @{$data->{requirements}};
  ok($agave, 'a component found on the items page is a requirement') or return;
  is($agave->{count}, 2, 'its count is the recipe quantity times the count');
  ok($agave->{id} && $agave->{item_type}, 'requirement has id and item_type');
  is_deeply([ map { $_->{reason} } @{$data->{missing}} ], ['material_not_found'], 'a component off the page is reported as missing');
};

subtest 'calculate_requirements tool - base materials' => sub {
  my ($tool) = grep { $_->name eq 'calculate_requirements' } @{$mcp->server->tools};

  my $result = $tool->code->($tool, {
    items => [{ item => 'Agave Juice', count => 1 }],
    base_only => 1,
  });
  ok($result, 'returns result');

  my $data = eval { $json->decode($result) };
  ok(!$@, 'result is valid JSON') or diag("Error: $@");
  ok(ref $data eq 'HASH', 'result is hash');
  ok(exists $data->{requirements}, 'has requirements');
  ok(exists $data->{missing}, 'has missing');

  my $req = $data->{requirements}[0];
  ok($req->{item_type}, 'requirement has item_type');
  is($req->{item}, 'Agave', 'the base material');
  ok($req->{count}, 'requirement has count');
};

done_testing;
