#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use File::Temp ();
use FindBin;
use lib "$FindBin::Bin/lib";
use ArcTest;
use FrozenClock;

my $ua  = ArcTest::ua();
my $mcp = ArcTest::mcp(ua => $ua);

sub data { return ArcTest::decode(ArcTest::call($mcp, @_)) }

subtest 'the tool list' => sub {
  my %tools = map { $_->name => $_ } @{ $mcp->server->tools };
  ok($tools{$_}, "$_ is registered") for qw(
    search_items get_item_details get_arcs get_quests get_traders find_item_seller
    get_event_timers get_active_events get_map_data list_maps calculate_requirements
    get_ermal get_hideout get_weekly_trials
  );
};

subtest 'the server names its source' => sub {
  my $server = $mcp->server;
  like($server->instructions, qr{MetaForge}, 'the instructions name MetaForge');
  like($server->instructions, qr{https://metaforge\.app/arc-raiders}, 'and link to it');
};

subtest 'get_ermal' => sub {
  my $ermal = data('get_ermal');
  is(ref $ermal, 'HASH', 'one object');
  is(scalar @{ $ermal->{offers} }, 10, 'ten offers');
  is(scalar @{ $ermal->{permanent_services} }, 2, 'two permanent services');
  ok($ermal->{synced_at}, 'synced_at');

  my ($anvil) = grep { $_->{offer_title} eq 'Anvil II' } @{ $ermal->{offers} };
  is($anvil->{coin_cost}, 20000, 'coin cost');
  is($anvil->{item}{id}, 'anvil-ii', 'the item of the offer');
  ok($anvil->{offer_end}, 'the offer period');
  ok(@{ $anvil->{accepted_items} } > 0, 'the accepted items');
  is_deeply([ map { $_->{id} } @{ $ermal->{permanent_services} } ], [qw(expedition-vault stash-expansion)], 'the services');
};

subtest 'get_hideout' => sub {
  my $all = data('get_hideout');
  is(scalar @$all, 9, 'nine stations');
  my ($gun) = grep { $_->{id} eq 'weapon-bench' } @$all;
  is($gun->{name}, 'Gunsmith', 'name');
  is($gun->{max_level}, 4, 'max_level');
  is_deeply([ map { $_->{level} } @{ $gun->{levels} } ], [1 .. 4], 'levels in order');
  is_deeply($gun->{levels}[0]{required_items}[0], { id => 'metal-parts', quantity => 20 }, 'what level 1 needs');
  is_deeply($gun->{levels}[0]{unlock_requirements}, [{ id => 'rounds-played', quantity => 3 }], 'unlock requirements');
  ok(exists $gun->{levels}[1]{crafts}, 'crafts');

  my ($scrappy) = grep { $_->{id} eq 'scrappy' } @$all;
  is_deeply($scrappy->{levels}[0]{required_items}, [], 'a level without needs has an empty list');

  my $by_name = data('get_hideout', { station => 'gunsmith' });
  is_deeply([ map { $_->{id} } @$by_name ], ['weapon-bench'], 'station by name, case-insensitive');
  my $by_id = data('get_hideout', { station => 'weapon-bench', level => 2 });
  is(scalar @{ $by_id->[0]{levels} }, 1, 'one level');
  is($by_id->[0]{levels}[0]{level}, 2, 'the level asked for');
  is_deeply(
    [ map { "$_->{id}:$_->{quantity}" } @{ $by_id->[0]{levels}[0]{required_items} } ],
    ['rusted-tools:3', 'mechanical-components:5', 'wasp-driver:8'], 'its items');

  my $level_one = data('get_hideout', { level => 1 });
  is(scalar @$level_one, 9, 'level 1 exists on every station');
  is(ArcTest::call($mcp, 'get_hideout', { station => 'nowhere' }), "No hideout station found matching 'nowhere'", 'unknown station');
  is(ArcTest::call($mcp, 'get_hideout', { station => 'scrappy', level => 9 }), 'No hideout level 9 found', 'unknown level');
};

subtest 'get_weekly_trials' => sub {
  my $trials = data('get_weekly_trials');
  is(ref $trials, 'HASH', 'one object');
  is_deeply($trials->{window}, {
    active_window_end => '2026-11-03T10:00:00Z',
    next_window_start => '2026-11-03T12:00:00Z',
  }, 'the window as ISO 8601 UTC');

  my @list = @{ $trials->{trials} };
  ok(@list, 'trials');
  ok((!grep { !$_->{is_active} && !$_->{upcoming} } @list), 'only running and coming ones');
  is(scalar(grep { $_->{is_active} } @list), 5, 'five are running');
  is(scalar(grep { $_->{upcoming} } @list), 5, 'five are coming');

  my ($husks) = grep { $_->{trial_id} eq 'd9bPJuXx' } @list;
  is($husks->{name}, 'Search Husks', 'name');
  is($husks->{window_start}, '2026-10-27T12:00:00Z', 'window start');
  is($husks->{window_end}, '2026-11-03T10:00:00Z', 'window end');
  is($husks->{multiplier}, 400, 'multiplier');
  ok(ref $husks->{parameters} eq 'ARRAY', 'parameters');
  like($husks->{guide_link}, qr{^https://metaforge\.app/}, 'guide link');

  my $all = data('get_weekly_trials', { include_all => 1 });
  is(scalar @{ $all->{trials} }, 136, 'include_all lists the catalogue');
  ok((grep { !$_->{is_active} && !$_->{upcoming} } @{ $all->{trials} }), 'with the ones that are neither');
};

subtest 'events take a region' => sub {
  my $before = () = $ua->requests;
  for my $name (qw(get_event_timers get_active_events)) {
    my $tool = ArcTest::tool($mcp, $name);
    is_deeply($tool->input_schema->{properties}{region}{enum}, [qw(europe north-america oceania east-asia brazil all)], "$name offers the regions");
    ok($tool->validate_input({ region => 'brazil' }) == 0, "$name accepts brazil");
    ok($tool->validate_input({ region => 'mars' }), "$name refuses an unknown region");
  }

  FrozenClock::at('2026-11-03T08:30:00', sub { ArcTest::call($mcp, 'get_event_timers', { region => 'north-america' }) });
  my @requests = grep { /events-schedule/ } ($ua->requests)[$before .. $#{[$ua->requests]}];
  like($requests[0], qr/[?&]region=north-america\b/, 'the region goes to the API');

  FrozenClock::at('2026-11-03T08:30:00', sub { ArcTest::call($mcp, 'get_active_events', {}) });
  my ($last) = grep { /events-schedule/ } reverse $ua->requests;
  unlike($last, qr/region=/, 'no region parameter without a region');
};

subtest 'get_item_details passes the new item fields' => sub {
  my $api = $mcp->api;

  my ($powercell) = grep { $_->name eq 'Advanced ARC Powercell' } @{ $api->items(includeComponents => 'true') };
  my $details = $mcp->_item_details_to_hash($powercell);
  is(scalar @{ $details->{recycle_from} }, 2, 'recycle_from');
  is_deeply([ sort keys %{ $details->{recycle_from}[0] } ], [qw(id name quantity)], 'as id, name, quantity');
  is(scalar @{ $details->{dropped_by} }, 11, 'dropped_by');
  is_deeply([ sort keys %{ $details->{dropped_by}[0] } ], [qw(id name)], 'as ARC id and name');
  is(scalar @{ $details->{used_in} }, 4, 'used_in');
  is_deeply($details->{mods}, [], 'no mods');
  is_deeply($details->{locations}, [], 'no locations');
  ok(exists $details->{$_}, "$_ is there") for qw(subcategory flavor_text ammo_type shield_type loot_area guide_url);

  my %by_name = map { $_->name => $_ } @{ $api->items(page => 15, includeComponents => 'true') };
  my $hairpin = $mcp->_item_details_to_hash($by_name{'Hairpin I'});
  is_deeply($hairpin->{mods}, [{ id => 'extended-light-mag-i', name => 'Extended Light Mag I' }], 'mods');
  my $gun_parts = $mcp->_item_details_to_hash($by_name{'Heavy Gun Parts'});
  ok(@{ $gun_parts->{recycle_from} } >= 20, 'weapons recycle into Heavy Gun Parts');
  ok((grep { $_->{name} eq 'Anvil I' && $_->{quantity} == 2 } @{ $gun_parts->{recycle_from} }), 'with their quantity');
  is_deeply([ map { $_->{id} } @{ $gun_parts->{dropped_by} } ], [ map { $_->{arc}{id} } @{ $by_name{'Heavy Gun Parts'}->dropped_by } ], 'dropped_by ARC ids');

  my %by_name20 = map { $_->name => $_ } @{ $api->items(page => 20, includeComponents => 'true') };
  my $key = $mcp->_item_details_to_hash($by_name20{'Patrol Car Key'});
  is_deeply($key->{locations}, [{ id => 'ca792d5687618106082c5a2271b8c042', map => 'dam' }], 'locations');
};

subtest 'the other shapers pass the new fields' => sub {
  my ($arc) = grep { $_->name eq 'ARC Surveyor' } @{ $mcp->api->arcs(includeLoot => 'true') };
  my $hash = $mcp->_arc_to_hash($arc);
  ok(ref $hash->{data} eq 'HASH' && exists $hash->{data}{variants}, 'ARC data with its variants');

  my ($marker) = @{ $mcp->api->map_data(map => 'dam') };
  ok(exists $mcp->_marker_to_hash($marker)->{community}, 'marker community');
};

subtest 'find_item_seller' => sub {
  my $trader = data('find_item_seller', { item_name => 'Adrenaline Shot' });
  is_deeply([ map { $_->{trader} } @$trader ], ['Lance'], 'a trader item as before');
  ok(exists $trader->[0]{item}{trader_price}, 'with its trader_price');

  my $ermal = data('find_item_seller', { item_name => 'Anvil II' });
  is_deeply([ map { $_->{trader} } @$ermal ], ['Ermal'], 'Ermal sells Anvil II');
  is($ermal->[0]{coin_cost}, 20000, 'for coins');
  ok($ermal->[0]{offer_end}, 'until offer_end');
  ok(@{ $ermal->[0]{accepted_items} }, 'against accepted items');
  is($ermal->[0]{item}{id}, 'anvil-ii', 'the item');

  is(ArcTest::call($mcp, 'find_item_seller', { item_name => 'Nothing At All' }), "No traders found selling 'Nothing At All'", 'nobody sells it');
};

subtest 'get_traders keeps the traders apart from Ermal' => sub {
  my $traders = data('get_traders');
  is_deeply([ map { $_->{name} } @$traders ], [qw(Apollo Celeste Lance Shani TianWen)], 'five traders');
};

subtest 'the cache expires the offers' => sub {
  local $ENV{XDG_CACHE_HOME} = File::Temp::tempdir(CLEANUP => 1);
  my $cache = MCP::ArcRaiders->new->cache;
  is($cache->ttl->{traders}, 3600, 'trader offers live an hour');
};

done_testing;
