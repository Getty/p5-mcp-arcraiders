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

  my $result = $tool->code->($tool, { search => 'Ferro', limit => 10 });
  ok($result, 'returns result');

  my $data = eval { $json->decode($result) };
  ok(!$@, 'result is valid JSON');
  ok(ref $data eq 'ARRAY', 'result is array');
  ok(@$data > 0, 'has items');

  my $ferro = $data->[0];
  like($ferro->{name}, qr/Ferro/i, 'found Ferro item');
};

subtest 'get_item_details tool' => sub {
  my ($tool) = grep { $_->name eq 'get_item_details' } @{$mcp->server->tools};
  ok($tool, 'get_item_details tool exists');

  my $result = $tool->code->($tool, { name => 'Ferro I' });
  ok($result, 'returns result');

  my $data = eval { $json->decode($result) };
  ok(!$@, 'result is valid JSON') or diag("Parse error: $@, result: $result");

  if (ref $data eq 'ARRAY' && @$data) {
    my $item = $data->[0];
    is($item->{name}, 'Ferro I', 'correct item name');
    ok(exists $item->{crafting_requirements}, 'has crafting_requirements');
  }
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

subtest 'list_maps tool' => sub {
  my ($tool) = grep { $_->name eq 'list_maps' } @{$mcp->server->tools};
  ok($tool, 'list_maps tool exists');

  my $result = $tool->code->($tool, {});
  ok($result, 'returns result');

  my $data = eval { $json->decode($result) };
  ok(!$@, 'result is valid JSON');
  ok(ref $data eq 'ARRAY', 'result is array');
  ok(@$data >= 5, 'has at least 5 maps');

  my @names = map { $_->{name} } @$data;
  ok((grep { /Dam/ } @names), 'contains Dam');
};

subtest 'calculate_requirements tool - direct' => sub {
  my ($tool) = grep { $_->name eq 'calculate_requirements' } @{$mcp->server->tools};
  ok($tool, 'calculate_requirements tool exists');

  my $result = $tool->code->($tool, {
    items => [{ item => 'Ferro II', count => 1 }],
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
    diag("Direct requirements for Ferro II: " . join(", ", @names));
  }
};

subtest 'calculate_requirements tool - base materials' => sub {
  my ($tool) = grep { $_->name eq 'calculate_requirements' } @{$mcp->server->tools};

  my $result = $tool->code->($tool, {
    items => [{ item => 'Ferro III', count => 1 }],
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
    diag("Base requirements for Ferro III: " . join(", ", @names));

    # Each requirement should have expected fields
    my $req = $data->{requirements}[0];
    ok($req->{item}, 'requirement has item name');
    ok($req->{count}, 'requirement has count');
  }
};

done_testing;
