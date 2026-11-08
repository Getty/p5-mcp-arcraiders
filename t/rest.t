#!/usr/bin/env perl
# The HTTP server: the REST routes and the OpenAPI description beside the MCP
# tools. The API runs on the MockUA fixtures, the cache in a temp directory.
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/lib";

BEGIN {
  $ENV{XDG_CACHE_HOME} = tempdir(CLEANUP => 1);
  require ArcTest;
  no warnings 'redefine';
  require WWW::MetaForge::ArcRaiders;
  *WWW::MetaForge::ArcRaiders::_build_ua = sub { ArcTest::ua() };
}

use Mojo::File qw(path);
use Mojo::Server;
use Test::Mojo;
use FrozenClock;

my $app = Mojo::Server->new->load_app(path($FindBin::Bin, '..', 'bin', 'mcp-arcraiders-http')->to_string);
my $t = Test::Mojo->new($app);

subtest 'the info page names the source and the routes' => sub {
  $t->get_ok('/')->status_is(200)
    ->json_is('/source/name', 'MetaForge')
    ->json_is('/source/url', 'https://metaforge.app/arc-raiders')
    ->json_has('/endpoints/rest/item_sellers')
    ->json_has('/endpoints/rest/ermal')
    ->json_has('/endpoints/rest/hideout')
    ->json_has('/endpoints/rest/weekly_trials');
};

subtest 'the OpenAPI description' => sub {
  $t->get_ok('/openapi.json')->status_is(200);
  my $spec = $t->tx->res->json;

  like($spec->{info}{description}, qr{MetaForge, https://metaforge\.app/arc-raiders}, 'info names the source with the link');
  is($spec->{info}{'x-data-source'}{url}, 'https://metaforge.app/arc-raiders', 'and says so in a field of its own');

  my $map = (grep { $_->{name} eq 'map' } @{ $spec->{paths}{'/api/maps/{map}'}{get}{parameters} })[0];
  is_deeply($map->{schema}{enum}, [ WWW::MetaForge::ArcRaiders->maps ], 'the map enum is the list of the API object');
  ok((grep { $_ eq 'pendola-pass' } @{ $map->{schema}{enum} }), 'pendola-pass among them');

  ok(!(grep { $_->{name} eq 'type' } @{ $spec->{paths}{'/api/quests'}{get}{parameters} // [] }), 'quests take no type');

  for my $path ('/api/events', '/api/events/active') {
    my ($region) = grep { $_->{name} eq 'region' } @{ $spec->{paths}{$path}{get}{parameters} };
    is_deeply($region->{schema}{enum}, [qw(europe north-america oceania east-asia brazil all)], "$path takes a region");
  }

  for my $path (qw(/api/ermal /api/hideout /api/weekly-trials)) {
    ok($spec->{paths}{$path}{get}{operationId}, "$path is described");
  }
};

subtest 'every MCP tool has its REST route and OpenAPI path' => sub {
  my %route_of = (
    search_items => '/api/items', get_item_details => '/api/items/{name}',
    get_arcs => '/api/arcs', get_quests => '/api/quests', get_quest_details => '/api/quests/{quest}', get_traders => '/api/traders',
    find_item_seller => '/api/items/{name}/sellers',
    get_event_timers => '/api/events', get_active_events => '/api/events/active',
    get_map_data => '/api/maps/{map}', list_maps => '/api/maps',
    calculate_requirements => '/api/requirements',
    get_ermal => '/api/ermal', get_hideout => '/api/hideout', get_weekly_trials => '/api/weekly-trials',
  );
  my $spec = $t->get_ok('/openapi.json')->tx->res->json;
  my %tools = map { $_->name => 1 } @{ ArcTest::mcp()->server->tools };
  is_deeply([ sort keys %tools ], [ sort keys %route_of ], 'the table covers every tool');
  ok($spec->{paths}{$route_of{$_}}, "$_ has an OpenAPI path $route_of{$_}") for sort keys %route_of;
};

subtest 'REST answers like the tools' => sub {
  my $mcp = ArcTest::mcp();
  for my $case (
    [ '/api/ermal'                           => 'get_ermal',          {} ],
    [ '/api/hideout?station=weapon-bench'    => 'get_hideout',        { station => 'weapon-bench' } ],
    [ '/api/hideout?level=2'                 => 'get_hideout',        { level => 2 } ],
    [ '/api/weekly-trials'                   => 'get_weekly_trials',  {} ],
    [ '/api/weekly-trials?include_all=1'     => 'get_weekly_trials',  { include_all => 1 } ],
    [ '/api/arcs'                            => 'get_arcs',           {} ],
    [ '/api/traders'                         => 'get_traders',        {} ],
    [ '/api/items/Adrenaline%20Shot/sellers' => 'find_item_seller',   { item_name => 'Adrenaline Shot' } ],
    [ '/api/items/Anvil%20II/sellers'        => 'find_item_seller',   { item_name => 'Anvil II' } ],
    [ '/api/quests'                          => 'get_quests',         {} ],
    [ '/api/quests?trader=Celeste&name=journals' => 'get_quests',     { trader => 'Celeste', name => 'journals' } ],
    [ '/api/quests/a-bad-feeling'            => 'get_quest_details',  { quest => 'a-bad-feeling' } ],
    [ '/api/items/Adrenaline%20Shot'         => 'get_item_details',   { name => 'Adrenaline Shot' } ],
    [ '/api/maps/pendola-pass?category=arc'  => 'get_map_data',       { map => 'pendola-pass', category => 'arc' } ],
  ) {
    my ($url, $tool, $args) = @$case;
    my $rest = $t->get_ok($url)->status_is(200)->tx->res->json;
    is_deeply($rest, ArcTest::decode(ArcTest::call($mcp, $tool, $args)), "$url equals $tool");
  }
};

subtest 'REST: quests over all pages' => sub {
  $t->get_ok('/api/quests')->status_is(200);
  is(scalar @{ $t->tx->res->json }, 123, '123 quests');
  ok(!exists $t->tx->res->json->[0]{manifest}, 'as the short overview');
  $t->get_ok('/api/quests/a-bad-feeling')->status_is(200)->json_has('/manifest');
  $t->get_ok('/api/quests/nope')->status_is(404);
};

subtest 'REST: events by region' => sub {
  FrozenClock::at('2026-11-03T08:30:00', sub { $t->get_ok('/api/events?region=oceania')->status_is(200) });
  ok(scalar @{ $t->tx->res->json }, 'events');
  ok(exists $t->tx->res->json->[0]{region}, 'with a region field');
  $t->get_ok('/api/events/active?region=mars')->status_is(400)->json_like('/error', qr/region must be one of/);
  $t->get_ok('/api/events?region=mars')->status_is(400);
};

subtest 'REST: item sellers' => sub {
  $t->get_ok('/api/items/Nothing%20At%20All/sellers')->status_is(404)->json_has('/error');
};

subtest 'REST: hideout errors' => sub {
  $t->get_ok('/api/hideout?station=nowhere')->status_is(404)->json_like('/error', qr/nowhere/);
  $t->get_ok('/api/hideout?level=x')->status_is(400);
  $t->get_ok('/api/hideout?station=scrappy&level=9')->status_is(404);
};

subtest 'REST: map data' => sub {
  $t->get_ok('/api/maps/pendola-pass?category=locations&subcategory=extraction')->status_is(200)
    ->json_is('/0/name', 'Reckless Transceiver');
  $t->get_ok('/api/maps/dam')->status_is(400);
  $t->get_ok('/api/maps/dam?category=arc&search=nothing-like-this')->status_is(404);
};

subtest 'REST: requirements' => sub {
  $t->post_ok('/api/requirements' => json => { items => [{ item => 'Agave Juice', count => 2 }] })->status_is(200)
    ->json_is('/requirements/0/item', 'Agave')
    ->json_is('/requirements/0/count', 2)
    ->json_is('/missing/0/reason', 'material_not_found');
};

done_testing;
