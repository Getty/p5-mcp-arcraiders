#!/usr/bin/env perl
# Opt-in live run: every tool once against the real MetaForge API.
#
#   USE_LIVE_API=1 timeout 600 prove -lv t/live.t
#
# Requests are spaced (LIVE_PAUSE seconds, default 0.5; 1 s between the tools),
# every request has a 20 s timeout and every tool an alarm. The run is
# skipped without USE_LIVE_API. Data: MetaForge, https://metaforge.app/arc-raiders
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use LWP::UserAgent;
use Time::HiRes ();

plan skip_all => 'live run, set USE_LIVE_API=1 to run it' unless $ENV{USE_LIVE_API};

use JSON::MaybeXS ();
use MCP::ArcRaiders;
use WWW::MetaForge::ArcRaiders;
use WWW::MetaForge::Cache;

my $PAUSE = $ENV{LIVE_PAUSE} // 0.5;

{
  package PausedUA;
  # The real user agent, one request per PAUSE seconds
  sub new { my ($class, %args) = @_; return bless { %args }, $class }
  sub request {
    my ($self, $request) = @_;
    Time::HiRes::sleep($self->{pause});
    Test::More::diag("GET " . $request->uri);
    return $self->{ua}->request($request);
  }
}

my $ua = PausedUA->new(
  pause => $PAUSE,
  ua    => LWP::UserAgent->new(agent => 'MCP-ArcRaiders-live-test', timeout => 20),
);
my $cache = WWW::MetaForge::Cache->new(namespace => 'mcp-arcraiders-live', cache_dir => tempdir(CLEANUP => 1));
my $api   = WWW::MetaForge::ArcRaiders->new(ua => $ua, cache => $cache);
my $mcp   = MCP::ArcRaiders->new(api => $api, cache => $cache);
my $json  = JSON::MaybeXS->new(utf8 => 0);

# Calls a tool with an alarm; returns the decoded answer (or the plain sentence)
sub run_tool {
  my ($name, $args, $seconds) = @_;
  my $started = time;
  my $text = eval {
    local $SIG{ALRM} = sub { die "alarm after $seconds s\n" };
    alarm($seconds // 150);
    my ($tool) = grep { $_->name eq $name } @{ $mcp->server->tools };
    die "no tool $name\n" unless $tool;
    my $answer = $tool->code->($tool, $args);
    alarm(0);
    $answer;
  };
  alarm(0);
  my $error = $@;
  sleep 1;
  diag(sprintf '%s: %s in %d s', $name, $error ? "failed ($error)" : 'ok', time - $started);
  return (undef, $error) if $error;
  my $data = eval { $json->decode($text) };
  return ($data // $text, undef);
}

sub tool_ok {
  my ($name, $args, $seconds) = @_;
  my ($data, $error) = run_tool($name, $args, $seconds);
  ok(!$error, "$name answers") or diag($error);
  return $data;
}

subtest 'search_items' => sub {
  my $data = tool_ok('search_items', { search => 'Ferro', limit => 5 });
  ok(ref $data eq 'ARRAY' && @$data, 'items') or return;
  ok($data->[0]{id} && $data->[0]{name}, 'id and name');
};

subtest 'get_item_details' => sub {
  my $data = tool_ok('get_item_details', { name => 'Advanced ARC Powercell' });
  ok(ref $data eq 'ARRAY' && @$data, 'items') or return;
  my ($item) = grep { $_->{name} eq 'Advanced ARC Powercell' } @$data;
  ok($item, 'the item') or return;
  ok(@{ $item->{used_in} }, 'used_in');
  ok(@{ $item->{dropped_by} }, 'dropped_by');
  ok(@{ $item->{recycle_from} }, 'recycle_from');
};

subtest 'get_arcs' => sub {
  my $data = tool_ok('get_arcs', {});
  ok(ref $data eq 'ARRAY' && @$data >= 20, 'ARCs') or return;
  ok((grep { @{ $_->{loot} } } @$data), 'with loot');
  ok((grep { %{ $_->{data} } } @$data), 'some with data');
};

subtest 'get_quests' => sub {
  my $data = tool_ok('get_quests', {}, 200);
  ok(ref $data eq 'ARRAY' && @$data > 40, 'more than page 1') or return;
  ok(!exists $data->[0]{manifest}, 'as the overview');
  diag(scalar(@$data) . ' quests');
  my $one = tool_ok('get_quest_details', { quest => $data->[0]{id} });
  ok(ref $one eq 'HASH' && $one->{manifest}, 'one quest in full, with the manifest');
};

my @sellable;
subtest 'get_traders' => sub {
  my $data = tool_ok('get_traders', {});
  ok(ref $data eq 'ARRAY' && @$data >= 5, 'traders') or return;
  @sellable = map { $_->{inventory}[0]{name} } grep { @{ $_->{inventory} } } @$data;
};

subtest 'find_item_seller' => sub {
  my $name = $sellable[0] // 'Adrenaline Shot';
  my $data = tool_ok('find_item_seller', { item_name => $name });
  ok(ref $data eq 'ARRAY' && @$data, "a seller of $name") or return;
  ok($data->[0]{trader}, 'trader');
};

subtest 'get_ermal' => sub {
  my $data = tool_ok('get_ermal', {});
  ok(ref $data eq 'HASH' && @{ $data->{permanent_services} }, 'services') or return;
  ok(ref $data->{offers} eq 'ARRAY', 'offers');
};

subtest 'get_hideout' => sub {
  my $data = tool_ok('get_hideout', {});
  ok(ref $data eq 'ARRAY' && @$data >= 9, 'stations') or return;
  my $level = tool_ok('get_hideout', { station => $data->[1]{id}, level => 2 });
  ok(ref $level eq 'ARRAY' && @{ $level->[0]{levels} } == 1, 'one level of one station');
};

subtest 'get_weekly_trials' => sub {
  my $data = tool_ok('get_weekly_trials', {});
  ok(ref $data eq 'HASH' && $data->{window}{next_window_start}, 'the window') or return;
  ok(ref $data->{trials} eq 'ARRAY', 'trials');
  diag(scalar(@{ $data->{trials} }) . ' running or coming');
};

subtest 'get_event_timers and get_active_events' => sub {
  my $data = tool_ok('get_event_timers', {});
  ok(ref $data eq 'ARRAY' && @$data, 'events') or return;
  my $na = tool_ok('get_event_timers', { region => 'north-america' });
  ok(ref $na eq 'ARRAY' && @$na, 'events of north-america');
  my $active = tool_ok('get_active_events', {});
  ok(ref $active eq 'ARRAY' || $active =~ /No events/, 'active events or the sentence');
};

subtest 'list_maps and get_map_data' => sub {
  my $maps = tool_ok('list_maps', {});
  ok(ref $maps eq 'ARRAY' && (grep { $_->{id} eq 'pendola-pass' } @$maps), 'maps with pendola-pass') or return;
  my $data = tool_ok('get_map_data', { map => 'pendola-pass', category => 'locations', subcategory => 'extraction' });
  ok(ref $data eq 'ARRAY' && @$data, 'extraction points') or return;
  ok(defined $data->[0]{x} && defined $data->[0]{y}, 'coordinates');
};

subtest 'calculate_requirements' => sub {
  my $direct = tool_ok('calculate_requirements', { items => [{ item => 'Adrenaline Shot', count => 2 }] }, 300);
  ok(ref $direct eq 'HASH' && @{ $direct->{requirements} }, 'direct requirements') or return;
  my $base = tool_ok('calculate_requirements', { items => [{ item => 'Adrenaline Shot', count => 2 }], base_only => 1 }, 60);
  ok(ref $base eq 'HASH' && @{ $base->{requirements} }, 'base requirements');
};

done_testing;
