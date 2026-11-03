package FrozenClock;
use strict;
use warnings;
use DateTime;

# Freezes DateTime->now at a fixed UTC time, so no test depends on the real
# clock. Only the code run inside the block sees the frozen time:
#
#   FrozenClock::at('2026-11-03T05:30:00', sub { ... });
#
# The event code takes the time from DateTime->now and nowhere else.

sub at {
  my ($iso, $code) = @_;
  my ($y, $mo, $d, $h, $mi, $s) = $iso =~ /^(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+)$/
    or die "FrozenClock: bad time '$iso'\n";
  my $epoch = DateTime->new(
    year => $y, month => $mo, day => $d, hour => $h, minute => $mi, second => $s,
    time_zone => 'UTC',
  )->epoch;
  no warnings 'redefine';
  local *DateTime::now = sub {
    my ($class, %args) = @_;
    return DateTime->from_epoch(epoch => $epoch, %args);
  };
  return $code->();
}

1;
