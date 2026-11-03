#!/usr/bin/env perl
# A name with a typographic apostrophe goes through a tool and reaches the
# wire as UTF-8 exactly once: the tool hands over characters, the MCP
# framework encodes the whole response.
use strict;
use warnings;
use utf8;
use Test::More;
use FindBin;
use IPC::Open3;
use Symbol qw(gensym);
use Mojo::JSON qw(decode_json);
use JSON::MaybeXS ();
use lib "$FindBin::Bin/lib";
use ArcTest;

my $apostrophe = "\x{2019}";
my $once       = "Celeste${apostrophe}s Journals";
my $bytes_once = "Celeste\xE2\x80\x99s Journals";            # the UTF-8 bytes of the name
my $twice      = "Celeste\xC3\xA2\xC2\x80\xC2\x99s Journals"; # those bytes encoded again

# The server of the real stdio entry point, on the fixtures
my $script = <<'PERL';
use strict; use warnings;
use lib 'lib', 't/lib';
use ArcTest;
$ArcTest::FIXTURES = 't/fixtures';
ArcTest::mcp()->run_stdio;
PERL

sub stdio_answer {
  my (@requests) = @_;
  my $pid = open3(my $in, my $out, my $err = gensym, $^X, '-Ilib', '-It/lib', '-e', $script);
  binmode $in;
  binmode $out;
  print {$in} "$_\n" for @requests;
  close $in;
  my $answer = do { local $/; <$out> };
  waitpid $pid, 0;
  return $answer;
}

my @call = (
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}',
  '{"jsonrpc":"2.0","method":"notifications/initialized"}',
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_quests","arguments":{}}}',
);

subtest 'the bytes of the stdio answer' => sub {
  my $answer = stdio_answer(@call);
  ok(length $answer, 'the server answered');
  ok(index($answer, $bytes_once) >= 0, 'the name is UTF-8 encoded once (e2 80 99)');
  is(index($answer, $twice), -1, 'and not encoded twice');
  is(index($answer, "\xC3\xA2\xC2\x80"), -1, 'no double-encoded sequence anywhere');

  my ($line) = grep { /"id":2/ } split /\n/, $answer;
  my $response = decode_json($line);
  my $quests   = JSON::MaybeXS->new(utf8 => 0)->decode($response->{result}{content}[0]{text});
  my ($quest)  = grep { $_->{name} eq $once } @$quests;
  ok($quest, 'a client that decodes the response gets the name back as characters');
};

subtest 'the tool hands over characters' => sub {
  my $text = ArcTest::call(ArcTest::mcp(), 'get_quests', {});
  ok(utf8::is_utf8($text), 'a character string');
  ok(index($text, $once) >= 0, 'with the apostrophe as one character');
  is(index($text, $bytes_once), -1, 'not as its UTF-8 bytes');
};

subtest 'the former encoder doubled the encoding' => sub {
  # Control for the finding: a utf8 => 1 encoder (the former setting) gives
  # bytes, and the framework, encoding the response again, would turn them
  # into the doubled sequence.
  my $mcp  = MCP::ArcRaiders->new(
    api  => ArcTest::api(),
    json => JSON::MaybeXS->new(utf8 => 1, pretty => 1, canonical => 1, convert_blessed => 1),
  );
  my $text = ArcTest::call($mcp, 'get_quests', {});
  my $wire = Mojo::JSON::encode_json({ text => $text });
  ok(index($wire, $twice) >= 0, 'bytes in, doubled bytes out');
};

done_testing;
