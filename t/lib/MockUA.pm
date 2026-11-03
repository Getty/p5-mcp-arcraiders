package MockUA;
use strict;
use warnings;
use Path::Tiny;
use HTTP::Response;
use Encode;
use JSON::MaybeXS;

sub new {
  my ($class, %args) = @_;
  return bless {
    fixtures_dir => $args{fixtures_dir} // 't/fixtures',
  }, $class;
}

sub request {
  my ($self, $http_request) = @_;
  my $uri = $http_request->uri;

  my $fixture_file;
  if ($uri =~ /\/traders/) {
    $fixture_file = 'traders.json';
  } elsif ($uri =~ /\/items/) {
    $fixture_file = 'items.json';
  } elsif ($uri =~ /\/quests/) {
    $fixture_file = 'quests.json';
  } elsif ($uri =~ /\/events-schedule/) {
    $fixture_file = 'event-timers.json';
  } elsif ($uri =~ /\/arcs/) {
    $fixture_file = 'arcs.json';
  } elsif ($uri =~ /game-map-data/) {
    # Extract mapID from query string
    my ($map) = $uri =~ /mapID=([^&]+)/;
    $fixture_file = $map ? "map-data-$map.json" : 'map-data.json';
  } else {
    return HTTP::Response->new(404, 'Not Found');
  }

  my $file = path($self->{fixtures_dir}, $fixture_file);

  unless ($file->is_file) {
    return HTTP::Response->new(404, 'Fixture not found: ' . $fixture_file);
  }

  my $content = $file->slurp_utf8;

  # Page-aware pagination: fixtures are byte-faithful "page 1" responses that
  # report hasNextPage=true. _fetch_all_pages walks page=2,3,... until
  # hasNextPage goes false, so an endpoint that always returned page 1 would
  # loop forever. Honour the page query param: page 1 (or none) serves the
  # fixture verbatim; any later page is a synthesized terminal page with an
  # empty data set and hasNextPage=false, so multi-page fetches terminate
  # offline without hand-editing the byte-faithful fixture.
  my ($page) = $uri =~ /[?&]page=(\d+)/;
  if (defined $page && $page > 1) {
    my $decoded = eval { JSON::MaybeXS->new->decode($content) };
    if (ref $decoded eq 'HASH' && ref $decoded->{pagination} eq 'HASH') {
      $decoded->{data} = [];
      $decoded->{pagination}{page}        = int($page);
      $decoded->{pagination}{hasNextPage} = \0;
      $decoded->{pagination}{hasPrevPage} = \1;
      $content = JSON::MaybeXS->new->encode($decoded);
    }
  }

  # Query-param gating: the live API only sends the heavy relations when
  # asked for them (includeComponents on /items, includeLoot on /arcs). The
  # fixtures are captured with the flag set, so without it we strip the gated
  # fields -- a caller that forgets the param then sees empty data offline,
  # exactly as live (karr k12).
  my %gated;
  if ($fixture_file eq 'items.json' && $uri !~ /[?&]includeComponents=true\b/) {
    %gated = (components => [], recycle_components => [], sold_by => []);
  } elsif ($fixture_file eq 'arcs.json' && $uri !~ /[?&]includeLoot=true\b/) {
    %gated = (loot => undef);
  }
  if (%gated) {
    my $decoded = eval { JSON::MaybeXS->new->decode($content) };
    if (ref $decoded eq 'HASH' && ref $decoded->{data} eq 'ARRAY') {
      for my $row (grep { ref eq 'HASH' } @{$decoded->{data}}) {
        for my $key (keys %gated) {
          next unless exists $row->{$key};
          if (defined $gated{$key}) { $row->{$key} = [] } else { delete $row->{$key} }
        }
      }
      $content = JSON::MaybeXS->new->encode($decoded);
    }
  }

  my $response = HTTP::Response->new(200, 'OK');
  $response->content(Encode::encode('UTF-8', $content));
  $response->header('Content-Type' => 'application/json');

  return $response;
}

1;
