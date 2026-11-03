#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/lib";
use JSON::MaybeXS;

use_ok('MCP::ArcRaiders');
use_ok('WWW::MetaForge::ArcRaiders');

my $cache_dir = tempdir(CLEANUP => 1);
my $json = JSON::MaybeXS->new(utf8 => 0);

# Setup API - either live or mocked
my $api;
if ($ENV{USE_LIVE_API}) {
  diag("Using LIVE API");
  $api = WWW::MetaForge::ArcRaiders->new(
    cache_dir => $cache_dir,
    use_cache => 0,
    debug     => $ENV{WWW_METAFORGE_ARCRAIDERS_DEBUG},
  );
} else {
  diag("Using MockUA (set USE_LIVE_API=1 for real API tests)");
  require MockUA;
  $api = WWW::MetaForge::ArcRaiders->new(
    ua        => MockUA->new(fixtures_dir => "$FindBin::Bin/fixtures"),
    cache_dir => $cache_dir,
    use_cache => 0,
    debug     => $ENV{WWW_METAFORGE_ARCRAIDERS_DEBUG},
  );
}

# Create MCP::ArcRaiders with our API instance
my $mcp = MCP::ArcRaiders->new(api => $api);

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

  my $result = $tool->code->($tool, { name => 'Anvil I' });
  ok($result, 'returns result');

  my $data = eval { $json->decode($result) };
  ok(!$@, 'result is valid JSON') or diag("Parse error: $@, result: $result");
  ok(ref $data eq 'ARRAY' && @$data, 'has items') or return;

  my ($item) = grep { $_->{name} eq 'Anvil I' } @$data;
  ok($item, 'found Anvil I') or return;
  ok(@{ $item->{components} } > 0, 'has crafting components');
  ok(exists $item->{recycle_components}, 'has recycle_components');
  is($item->{sold_by}[0]{trader_name}, 'TianWen', 'sold_by names the trader');
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

  my $result = $tool->code->($tool, {});
  ok($result, 'returns result');

  my $data = eval { $json->decode($result) };
  ok(!$@, 'result is valid JSON');
  ok(ref $data eq 'ARRAY', 'result is array');

  if (@$data) {
    my $event = $data->[0];
    ok($event->{name}, 'event has name');
    ok(exists $event->{is_active_now}, 'has is_active_now');
    ok(exists $event->{times}, 'has times');
    ok(ref $event->{times} eq 'ARRAY' && @{ $event->{times} }, 'times is a list of slots');
    like($event->{times}[0]{start}, qr/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/, 'slot start is ISO 8601 UTC');
    ok(exists $event->{icon}, 'has icon');
  }
};

subtest 'get_quests tool' => sub {
  my ($tool) = grep { $_->name eq 'get_quests' } @{$mcp->server->tools};
  ok($tool, 'get_quests tool exists');

  my $result = $tool->code->($tool, {});
  ok($result, 'returns result');

  my $data = eval { $json->decode($result) };
  ok(!$@, 'result is valid JSON');
  ok(ref $data eq 'ARRAY', 'result is array');

  if (@$data) {
    my $quest = $data->[0];
    ok($quest->{name}, 'quest has name');
    ok(exists $quest->{trader_name}, 'quest has trader_name');
    ok(exists $quest->{xp}, 'quest has xp');
    ok(ref $quest->{rewards} eq 'ARRAY', 'quest rewards is a list');
  }
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
  }
};

subtest 'get_map_data tool' => sub {
  my ($tool) = grep { $_->name eq 'get_map_data' } @{$mcp->server->tools};
  ok($tool, 'get_map_data tool exists');

  my $result = $tool->code->($tool, { map => 'dam', category => 'arc', subcategory => 'tick' });
  my $data = eval { $json->decode($result) };
  ok(!$@, 'result is valid JSON') or diag("Parse error: $@, result: $result");
  ok(ref $data eq 'ARRAY' && @$data, 'has markers') or return;

  my $marker = $data->[0];
  is($marker->{category}, 'arc', 'marker category');
  is($marker->{subcategory}, 'tick', 'marker subcategory');
  ok(defined $marker->{x} && defined $marker->{y}, 'marker has coordinates');
  ok(exists $marker->{behind_locked_door}, 'marker has behind_locked_door');
};

subtest 'list_maps tool' => sub {
  my ($tool) = grep { $_->name eq 'list_maps' } @{$mcp->server->tools};
  ok($tool, 'list_maps tool exists');

  my $result = $tool->code->($tool, {});
  ok($result, 'returns result');

  my $data = eval { $json->decode($result) };
  ok(!$@, 'result is valid JSON');
  ok(ref $data eq 'ARRAY', 'result is array');
  ok(@$data >= 6, 'has at least 6 maps');
  ok((grep { $_->{id} eq 'riven-tides' } @$data), 'contains riven-tides');

  my @names = map { $_->{name} } @$data;
  ok((grep { /Dam/ } @names), 'contains Dam');
};

subtest 'calculate_requirements tool - direct' => sub {
  my ($tool) = grep { $_->name eq 'calculate_requirements' } @{$mcp->server->tools};
  ok($tool, 'calculate_requirements tool exists');

  my $result = $tool->code->($tool, {
    items => [{ item => 'Anvil I', count => 1 }],
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

  if (@{$data->{requirements}}) {
    my @names = map { $_->{item} } @{$data->{requirements}};
    diag("Direct requirements for Anvil I: " . join(", ", @names));
  }
};

subtest 'calculate_requirements tool - base materials' => sub {
  my ($tool) = grep { $_->name eq 'calculate_requirements' } @{$mcp->server->tools};

  my $result = $tool->code->($tool, {
    items => [{ item => 'Anvil II', count => 1 }],
    base_only => 1,
  });
  ok($result, 'returns result');

  my $data = eval { $json->decode($result) };
  ok(!$@, 'result is valid JSON') or diag("Error: $@");
  ok(ref $data eq 'HASH', 'result is hash');
  ok(exists $data->{requirements}, 'has requirements');
  ok(exists $data->{missing}, 'has missing');

  if (@{$data->{requirements}}) {
    my @names = map { $_->{item} } @{$data->{requirements}};
    diag("Base requirements for Anvil II: " . join(", ", @names));

    # Each requirement should have expected fields
    my $req = $data->{requirements}[0];
    ok($req->{item_type}, 'requirement has item_type');
    ok($req->{item}, 'requirement has item name');
    ok($req->{count}, 'requirement has count');
  }
};

done_testing;
