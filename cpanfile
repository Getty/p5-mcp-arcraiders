requires 'perl', '5.020';
requires 'JSON::MaybeXS';
requires 'MCP', '0.06';
requires 'Moo';
requires 'Mojolicious';
requires 'POSIX';
requires 'namespace::clean';
requires 'WWW::MetaForge', '0.003';

on 'test' => sub {
  requires 'DateTime';
  requires 'File::Temp';
  requires 'HTTP::Response';
  requires 'LWP::UserAgent';
  requires 'Path::Tiny';
  requires 'Test::More', '0.98';
};
