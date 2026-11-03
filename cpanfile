requires 'perl', '5.020';
requires 'JSON::MaybeXS';
requires 'MCP', '0.06';
requires 'Moo';
requires 'namespace::clean';
requires 'WWW::MetaForge', '0.003';

on 'test' => sub {
  requires 'File::Temp';
  requires 'HTTP::Response';
  requires 'Path::Tiny';
  requires 'Test::More', '0.98';
};
