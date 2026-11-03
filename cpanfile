requires 'perl', '5.020';
requires 'Moo';
requires 'MCP', '0.06';
requires 'WWW::MetaForge', '0.003';
requires 'JSON::MaybeXS';
requires 'namespace::clean';

on 'test' => sub {
  requires 'Test::More', '0.98';
  requires 'Path::Tiny';
  requires 'HTTP::Response';
  requires 'File::Temp';
};
