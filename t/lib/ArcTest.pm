package ArcTest;
# Shared set-up of the offline tests: an API object on the MockUA fixtures
use strict;
use warnings;
use FindBin;
use File::Temp qw(tempdir);
use JSON::MaybeXS;
use MockUA;
use WWW::MetaForge::ArcRaiders;
use MCP::ArcRaiders;

our $FIXTURES = "$FindBin::Bin/fixtures";

sub ua { return MockUA->new(fixtures_dir => $FIXTURES) }

sub api {
  my (%args) = @_;
  return WWW::MetaForge::ArcRaiders->new(
    ua        => $args{ua} // ua(),
    cache_dir => tempdir(CLEANUP => 1),
    use_cache => 0,
  );
}

sub mcp { return MCP::ArcRaiders->new(api => api(@_)) }

sub tool {
  my ($mcp, $name) = @_;
  my ($tool) = grep { $_->name eq $name } @{ $mcp->server->tools };
  return $tool;
}

# Runs a tool handler and decodes its answer (characters, as the framework gets it)
sub call {
  my ($mcp, $name, $args) = @_;
  my $tool = tool($mcp, $name) or die "no tool $name\n";
  return $tool->code->($tool, $args // {});
}

sub json { return JSON::MaybeXS->new(utf8 => 0) }

sub decode { return json()->decode($_[0]) }

1;
