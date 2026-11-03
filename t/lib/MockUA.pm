package MockUA;
use strict;
use warnings;
use Path::Tiny;
use HTTP::Response;
use LWP::UserAgent;
use URI;
use Encode;
use JSON::MaybeXS;

# Network lock: the offline suite never talks to the network. Loading MockUA
# makes any real LWP::UserAgent request die loudly with the URL, so a test
# that bypasses the mock cannot pass by accident.
{
  no warnings 'redefine';
  for my $method (qw(request simple_request)) {
    no strict 'refs';
    *{"LWP::UserAgent::$method"} = sub {
      my ($self, $http_request) = @_;
      my $target = ref $http_request && $http_request->can('uri')
        ? $http_request->method . ' ' . $http_request->uri
        : '(unknown request)';
      die "MockUA: network access blocked in the offline suite: $target\n";
    };
  }
}

# What this mock simplifies compared to the live API:
#  - fixtures are byte-faithful live responses (the map files hold a verbatim
#    excerpt of the markers); the mock only selects or gates what it serves
#  - /items and /quests: page 1 is <name>.json, page N is <name>-page-N.json
#    when that file exists, otherwise a synthesized terminal page (no data,
#    hasNextPage false), so a walk over all pages ends offline
#  - without includeComponents=true the item relations are left out and
#    without includeLoot=true the arc loot is left out, as live
#  - /events-schedule, /hideout and /weekly-trials serve their fixture
#    whatever the query; region, map and name are not evaluated
#  - every request is recorded, see requests()

my @ITEM_RELATIONS = qw(
  components dropped_by mods recycle_components recycle_from
  relationships sold_by used_in
);

sub new {
  my ($class, %args) = @_;
  return bless {
    fixtures_dir => $args{fixtures_dir} // 't/fixtures',
    requests     => [],
  }, $class;
}

# URIs (strings) of all requests this UA has answered, in order
sub requests { return @{ $_[0]{requests} } }

sub _json { return JSON::MaybeXS->new(canonical => 1) }

sub request {
  my ($self, $http_request) = @_;
  my $uri = $http_request->uri;
  push @{ $self->{requests} }, "$uri";

  my $name;
  my $path = URI->new($uri)->path;
  my %query = URI->new($uri)->query_form;
  my $page  = defined $query{page} && $query{page} =~ /^\d+$/ ? int($query{page}) : 1;

  my $fixture_file;
  if ($path =~ m{/traders$}) {
    $fixture_file = 'traders.json';
  } elsif ($path =~ m{/items$}) {
    $name = 'items';
  } elsif ($path =~ m{/quests$}) {
    $name = 'quests';
  } elsif ($path =~ m{/events-schedule$}) {
    $fixture_file = 'events-schedule.json';
  } elsif ($path =~ m{/hideout$}) {
    $fixture_file = 'hideout.json';
  } elsif ($path =~ m{/weekly-trials$}) {
    $fixture_file = 'weekly-trials.json';
  } elsif ($path =~ m{/arcs$}) {
    $fixture_file = 'arcs.json';
  } elsif ($path =~ m{/game-map-data$}) {
    my $map = $query{mapID};
    $fixture_file = $map ? "map-data-$map.json" : 'map-data.json';
  } else {
    return HTTP::Response->new(404, 'Not Found');
  }

  my $terminal;
  if ($name) {
    $fixture_file = $page == 1 ? "$name.json" : "$name-page-$page.json";
    if ($page > 1 && !path($self->{fixtures_dir}, $fixture_file)->is_file) {
      $fixture_file = "$name.json";
      $terminal = 1;
    }
  }

  my $file = path($self->{fixtures_dir}, $fixture_file);
  return HTTP::Response->new(404, 'Fixture not found: ' . $fixture_file)
    unless $file->is_file;

  my $content = $file->slurp_utf8;
  my $gate;

  if ($terminal) {
    my $decoded = $self->_json->decode($content);
    $decoded->{data} = [];
    $decoded->{pagination}{page}        = $page;
    $decoded->{pagination}{hasNextPage} = \0;
    $decoded->{pagination}{hasPrevPage} = \1;
    $content = $self->_json->encode($decoded);
  }

  # Query-param gating: the live API only sends the heavy relations when asked
  # for them. The fixtures are captured with the flag set, so without it the
  # gated keys are removed.
  if ($name && $name eq 'items' && ($query{includeComponents} // '') ne 'true') {
    $gate = sub { delete @{ $_[0] }{@ITEM_RELATIONS} };
  } elsif ($fixture_file eq 'arcs.json' && ($query{includeLoot} // '') ne 'true') {
    $gate = sub { delete $_[0]{loot} };
  }
  if ($gate) {
    my $decoded = $self->_json->decode($content);
    $gate->($_) for grep { ref eq 'HASH' } @{ $decoded->{data} };
    $content = $self->_json->encode($decoded);
  }

  my $response = HTTP::Response->new(200, 'OK');
  $response->content(Encode::encode('UTF-8', $content));
  $response->header('Content-Type' => 'application/json');

  return $response;
}

1;
