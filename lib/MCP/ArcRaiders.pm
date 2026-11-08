package MCP::ArcRaiders;
# ABSTRACT: MCP Server providing ARC Raiders game data for AI assistants

use Moo;
use MCP::Server;
use WWW::MetaForge::ArcRaiders;
use WWW::MetaForge::Cache;
use JSON::MaybeXS;
use POSIX qw(strftime);
use namespace::clean;

our $VERSION = '0.001';

our $SOURCE_NAME = 'MetaForge';
our $SOURCE_URL  = 'https://metaforge.app/arc-raiders';
our $SOURCE_TEXT = "ARC Raiders game data: $SOURCE_NAME, $SOURCE_URL";

# Server regions the events-schedule endpoint serves (an unknown region
# silently returns the europe schedule)
our @REGIONS = qw(europe north-america oceania east-asia brazil all);

has api => (
  is      => 'ro',
  lazy    => 1,
  builder => '_build_api',
);

has cache => (
  is      => 'ro',
  lazy    => 1,
  builder => '_build_cache',
);

has json => (
  is      => 'ro',
  lazy    => 1,
  default => sub { JSON::MaybeXS->new(pretty => 1, canonical => 1, convert_blessed => 1) },
);

has server => (
  is      => 'ro',
  lazy    => 1,
  builder => '_build_server',
);

sub _build_cache {
  my ($self) = @_;
  # The trader offers (Ermal's change weekly) must not outlive a long-running server
  return WWW::MetaForge::Cache->new(namespace => 'mcp-arcraiders', ttl => { traders => 3600 });
}

sub _build_api {
  my ($self) = @_;
  return WWW::MetaForge::ArcRaiders->new(cache => $self->cache);
}

sub _to_json {
  my ($self, $data) = @_;
  return $self->json->encode($data);
}

sub _item_to_hash {
  my ($self, $item) = @_;
  return {
    id          => $item->id,
    name        => $item->name,
    item_type   => $item->item_type,
    rarity      => $item->rarity,
    description => $item->description,
    weight      => $item->weight,
    stack_size  => $item->stack_size,
    value       => $item->value,
    stat_block  => $item->stat_block,
  };
}

sub _item_details_to_hash {
  my ($self, $item) = @_;
  return {
    %{ $self->_item_to_hash($item) },
    subcategory        => $item->subcategory,
    flavor_text        => $item->flavor_text,
    ammo_type          => $item->ammo_type,
    shield_type        => $item->shield_type,
    loot_area          => $item->loot_area,
    guide_url          => $item->guide_url,
    workbench          => $item->workbench,
    loadout_slots      => $item->loadout_slots,
    components         => $item->components,
    recycle_components => $item->recycle_components,
    sold_by            => $item->sold_by,
    used_in            => $self->_used_in_to_list($item),
    recycle_from       => $self->_recycle_from_to_list($item),
    dropped_by         => $self->_dropped_by_to_list($item),
    mods               => $self->_mods_to_list($item),
    locations          => $item->locations,
  };
}

sub _used_in_to_list {
  my ($self, $item) = @_;
  return [ map { { id => $_->{item}{id}, name => $_->{item}{name}, quantity => $_->{quantity} } } @{ $item->used_in } ];
}

# The items that recycle into this item
sub _recycle_from_to_list {
  my ($self, $item) = @_;
  return [ map { { id => $_->{item}{id}, name => $_->{item}{name}, quantity => $_->{quantity} } } @{ $item->recycle_from } ];
}

# The ARCs that drop this item
sub _dropped_by_to_list {
  my ($self, $item) = @_;
  return [ map { { id => $_->{arc}{id}, name => $_->{arc}{name} } } @{ $item->dropped_by } ];
}

# The modifications that fit this item
sub _mods_to_list {
  my ($self, $item) = @_;
  return [ map { { id => $_->{mod}{id}, name => $_->{mod}{name} } } @{ $item->mods } ];
}

sub _arc_to_hash {
  my ($self, $arc) = @_;
  return {
    id          => $arc->id,
    name        => $arc->name,
    description => $arc->description,
    loot        => $arc->loot,
    data        => $arc->data,
  };
}

sub _quest_to_hash {
  my ($self, $quest) = @_;
  return {
    id                 => $quest->id,
    name               => $quest->name,
    description        => $quest->description,
    trader_name        => $quest->trader_name,
    objectives         => $quest->objectives,
    required_items     => $quest->required_items,
    rewards            => $quest->rewards,
    additional_rewards => $quest->additional_rewards,
    granted_items      => $quest->granted_items,
    xp                 => $quest->xp,
    guide_url          => $quest->guide_url,
    manifest           => $quest->manifest,
  };
}

# The short form of a quest for the overview
sub _quest_summary_to_hash {
  my ($self, $quest) = @_;
  return {
    id             => $quest->id,
    name           => $quest->name,
    trader_name    => $quest->trader_name,
    xp             => $quest->xp,
    required_items => scalar @{ $quest->required_items },
    rewards        => scalar @{ $quest->rewards },
  };
}

sub _trader_to_hash {
  my ($self, $trader) = @_;
  return {
    name      => $trader->name,
    inventory => $trader->inventory,
  };
}

sub _time_slot_to_hash {
  my ($self, $slot) = @_;
  return {
    start => $slot->start->iso8601 . 'Z',
    end   => $slot->end->iso8601 . 'Z',
  };
}

sub _event_to_hash {
  my ($self, $event) = @_;
  return {
    name             => $event->name,
    map              => $event->map,
    region           => $event->region,
    icon             => $event->icon,
    times            => [ map { $self->_time_slot_to_hash($_) } @{ $event->times } ],
    is_active_now    => $event->is_active_now ? \1 : \0,
    time_until_start => $event->time_until_start,
    time_until_end   => $event->time_until_end,
  };
}

sub _marker_to_hash {
  my ($self, $marker) = @_;
  return {
    id                 => $marker->id,
    name               => $marker->name,
    type               => $marker->type,
    category           => $marker->category,
    subcategory        => $marker->subcategory,
    x                  => $marker->x,
    y                  => $marker->y,
    z                  => $marker->z,
    loot_areas         => $marker->lootAreas,
    behind_locked_door => $marker->behindLockedDoor ? \1 : \0,
    community          => $marker->community,
    source_id          => $marker->source_id,
    route_id           => $marker->route_id,
  };
}

sub _iso8601 {
  my ($self, $epoch) = @_;
  return undef unless defined $epoch;
  return strftime('%Y-%m-%dT%H:%M:%SZ', gmtime $epoch);
}

sub _ermal_to_hash {
  my ($self, $ermal) = @_;
  return {
    synced_at          => $ermal->synced_at,
    offers             => $ermal->offers,
    permanent_services => $ermal->permanent_services,
  };
}

sub _hideout_level_to_hash {
  my ($self, $level) = @_;
  return {
    level               => $level->number,
    required_items      => $level->required_items,
    unlock_requirements => $level->unlock_requirements,
    crafts              => $level->crafts,
  };
}

sub _hideout_station_to_hash {
  my ($self, $station, $levels) = @_;
  return {
    id        => $station->id,
    name      => $station->name,
    max_level => $station->max_level,
    levels    => [ map { $self->_hideout_level_to_hash($_) } @{ $levels // $station->levels } ],
  };
}

sub _trial_to_hash {
  my ($self, $trial) = @_;
  return {
    id             => $trial->id,
    trial_id       => $trial->trial_id,
    name           => $trial->name,
    type           => $trial->type,
    is_active      => $trial->is_active ? \1 : \0,
    upcoming       => $trial->upcoming ? \1 : \0,
    window_start   => $self->_iso8601($trial->window_start),
    window_end     => $self->_iso8601($trial->window_end),
    multiplier     => $trial->multiplier,
    parameters     => $trial->parameters,
    map_names      => $trial->map_names,
    guide_link     => $trial->guide_link,
    video_link     => $trial->video_link,
    image_url      => $trial->image_url,
    database_links => $trial->database_links,
    sort_order     => $trial->sort_order,
  };
}

sub _trial_window_to_hash {
  my ($self, $window) = @_;
  return {
    active_window_end => $self->_iso8601($window->active_window_end),
    next_window_start => $self->_iso8601($window->next_window_start),
  };
}

# Shared by the MCP tool and the REST route: Ermal's offers and services
sub _ermal_result {
  my ($self) = @_;
  my $ermal = $self->api->ermal or return;
  return $self->_ermal_to_hash($ermal);
}

# Shared: the stations (by id or name, case-insensitive) and levels asked for.
# Returns an error sentence as the second value when nothing matches.
sub _hideout_result {
  my ($self, %args) = @_;
  my @stations = @{ $self->api->hideout };

  if (defined $args{station} && length $args{station}) {
    my $wanted = lc $args{station};
    @stations = grep { lc $_->id eq $wanted || lc $_->name eq $wanted } @stations;
    return (undef, "No hideout station found matching '$args{station}'") unless @stations;
  }

  my @result;
  for my $station (@stations) {
    my @levels = @{ $station->levels };
    @levels = grep { $_->number == $args{level} } @levels if defined $args{level};
    next if defined $args{level} && !@levels;
    push @result, $self->_hideout_station_to_hash($station, \@levels);
  }

  return (undef, "No hideout level $args{level} found") unless @result;
  return (\@result);
}

# Shared: the trials running now and the coming ones (all of them with
# include_all), plus the window the answer was valid for
sub _weekly_trials_result {
  my ($self, %args) = @_;
  my @trials = @{ $self->api->weekly_trials };
  @trials = grep { $_->is_active || $_->upcoming } @trials unless $args{include_all};
  return {
    window => $self->_trial_window_to_hash($self->api->weekly_trials_window),
    trials => [ map { $self->_trial_to_hash($_) } @trials ],
  };
}

# Shared: the events (of one region, europe when none is given) from the
# hourly cache
sub _events {
  my ($self, %args) = @_;
  my %params;
  $params{region} = $args{region} if defined $args{region} && length $args{region};
  return $self->api->event_timers_hourly(%params);
}

# Shared: all quests over all pages (the API ignores a quest type)
sub _all_quests {
  my ($self) = @_;
  return $self->api->quests_all;
}

# Shared: the quest overview, narrowed by trader (exact) and name (substring)
sub _quest_overview {
  my ($self, %args) = @_;
  my @quests = @{ $self->_all_quests };
  if (defined $args{trader} && length $args{trader}) {
    @quests = grep { lc($_->trader_name // '') eq lc $args{trader} } @quests;
  }
  if (defined $args{name} && length $args{name}) {
    @quests = grep { index(lc $_->name, lc $args{name}) >= 0 } @quests;
  }
  return [ map { $self->_quest_summary_to_hash($_) } @quests ];
}

# Shared: the full quest by id or exact name (case-insensitive)
sub _quest_details {
  my ($self, $wanted) = @_;
  return unless defined $wanted && length $wanted;
  my $lc = lc $wanted;
  my ($quest) = grep { lc $_->id eq $lc || lc $_->name eq $lc } @{ $self->_all_quests };
  return $quest ? $self->_quest_to_hash($quest) : undef;
}

# Shared: the markers of one category, narrowed by subcategory and search term
sub _filter_markers {
  my ($self, $markers, %args) = @_;
  my @filtered = grep { ($_->category // '') eq $args{category} } @$markers;

  if ($args{subcategory}) {
    @filtered = grep { $_->subcategory && $_->subcategory eq $args{subcategory} } @filtered;
  }

  if ($args{search}) {
    my $search = lc($args{search});
    @filtered = grep {
      (defined $_->name && index(lc($_->name), $search) >= 0) ||
      (defined $_->subcategory && index(lc($_->subcategory), $search) >= 0)
    } @filtered;
  }

  return \@filtered;
}

# Shared: the traders (and Ermal's offers) that sell an item by exact name
sub _item_sellers {
  my ($self, $item_name) = @_;
  my @sellers;

  for my $trader (@{ $self->api->traders }) {
    if (my $item = $trader->find_item($item_name)) {
      push @sellers, {
        trader => $trader->name,
        item   => $item,
      };
    }
  }

  if (my $ermal = $self->api->ermal) {
    for my $offer (@{ $ermal->offers }) {
      my $item = $offer->{item};
      next unless $item && lc($item->{name} // '') eq lc $item_name;
      push @sellers, {
        trader         => 'Ermal',
        item           => $item,
        coin_cost      => $offer->{coin_cost},
        offer_start    => $offer->{offer_start},
        offer_end      => $offer->{offer_end},
        accepted_items => $offer->{accepted_items},
      };
    }
  }

  return \@sellers;
}

sub _requirement_to_hash {
  my ($self, $req) = @_;
  return {
    item      => $req->{item}->name,
    id        => $req->{item}->id,
    count     => $req->{count},
    item_type => $req->{item}->item_type,
    rarity    => $req->{item}->rarity,
  };
}

sub _build_server {
  my ($self) = @_;

  my $server = MCP::Server->new(
    name         => 'arcraiders',
    version      => $VERSION,
    instructions => "Answers questions about ARC Raiders: items, ARCs, quests, traders, Ermal, the hideout, weekly trials, events and maps. Source of the data: $SOURCE_NAME, $SOURCE_URL - name the source when you share it.",
  );

  # Tool: search_items
  $server->tool(
    name        => 'search_items',
    description => 'Search for items in ARC Raiders by name or keyword. Returns weapons, materials, consumables, mods etc.',
    input_schema => {
      type       => 'object',
      properties => {
        search => {
          type        => 'string',
          description => 'Search term to find items (e.g., "Ferro", "weapon", "medkit")',
        },
        limit => {
          type        => 'integer',
          description => 'Maximum number of results (default: 20)',
          default     => 20,
        },
      },
    },
    code => sub {
      my ($tool, $args) = @_;
      my %params;
      $params{search} = $args->{search} if $args->{search};
      $params{limit}  = $args->{limit} // 20;

      my $items = $self->api->items(%params);
      my @results = map { $self->_item_to_hash($_) } @$items;
      return $self->_to_json(\@results);
    },
  );

  # Tool: get_item_details
  $server->tool(
    name        => 'get_item_details',
    description => 'Get detailed information about a specific item including crafting components, recycle yield, who sells it and what it is used in.',
    input_schema => {
      type       => 'object',
      properties => {
        name => {
          type        => 'string',
          description => 'Exact or partial item name to look up',
        },
      },
      required => ['name'],
    },
    code => sub {
      my ($tool, $args) = @_;
      my $items = $self->api->items(
        search            => $args->{name},
        limit             => 5,
        includeComponents => 'true',
      );

      return "No items found matching '$args->{name}'" unless @$items;

      my @details = map { $self->_item_details_to_hash($_) } @$items;

      return $self->_to_json(\@details);
    },
  );

  # Tool: get_arcs
  $server->tool(
    name        => 'get_arcs',
    description => 'Get the ARCs (enemy machines) in the game together with the loot they drop.',
    input_schema => {
      type       => 'object',
      properties => {
        include_loot => {
          type        => 'boolean',
          description => 'Include loot drop information (default: true)',
          default     => 1,
        },
      },
    },
    code => sub {
      my ($tool, $args) = @_;
      my %params;
      $params{includeLoot} = 'true' if $args->{include_loot} // 1;

      my $arcs = $self->api->arcs(%params);
      my @results = map { $self->_arc_to_hash($_) } @$arcs;
      return $self->_to_json(\@results);
    },
  );

  # Tool: get_quests
  $server->tool(
    name        => 'get_quests',
    description => 'Get an overview of all quests (every page of the API): id, name, trader, XP and the number of required items and rewards. Narrow it by trader or name; use get_quest_details for one quest in full.',
    input_schema => {
      type       => 'object',
      properties => {
        trader => {
          type        => 'string',
          description => 'Only the quests of this trader (exact name, case-insensitive)',
        },
        name => {
          type        => 'string',
          description => 'Only the quests whose name contains this text (case-insensitive)',
        },
      },
    },
    code => sub {
      my ($tool, $args) = @_;
      my $quests = $self->_quest_overview(%$args{qw(trader name)});

      return "No quests found" unless @$quests;
      return $self->_to_json($quests);
    },
  );

  # Tool: get_quest_details
  $server->tool(
    name        => 'get_quest_details',
    description => 'Get one quest in full: description, objectives, required items, all rewards and the manifest with prerequisites and objective graph.',
    input_schema => {
      type       => 'object',
      properties => {
        quest => {
          type        => 'string',
          description => 'Quest id or exact name (case-insensitive), e.g. "a-bad-feeling" or "A Bad Feeling"',
        },
      },
      required => ['quest'],
    },
    code => sub {
      my ($tool, $args) = @_;
      my $quest = $self->_quest_details($args->{quest});

      return "No quest found matching '$args->{quest}'" unless $quest;
      return $self->_to_json($quest);
    },
  );

  # Tool: get_traders
  $server->tool(
    name        => 'get_traders',
    description => 'Get trader NPCs and their current inventory. Shows what items each trader sells and their prices.',
    input_schema => {
      type       => 'object',
      properties => {},
    },
    code => sub {
      my ($tool, $args) = @_;
      my $traders = $self->api->traders;
      my @results = map { $self->_trader_to_hash($_) } @$traders;
      return $self->_to_json(\@results);
    },
  );

  # Tool: find_item_seller
  $server->tool(
    name        => 'find_item_seller',
    description => 'Find which traders (and which of Ermal\'s offers) sell a specific item.',
    input_schema => {
      type       => 'object',
      properties => {
        item_name => {
          type        => 'string',
          description => 'Name of the item to find',
        },
      },
      required => ['item_name'],
    },
    code => sub {
      my ($tool, $args) = @_;
      my $item_name = $args->{item_name};
      my $sellers = $self->_item_sellers($item_name);

      return "No traders found selling '$item_name'" unless @$sellers;
      return $self->_to_json($sellers);
    },
  );

  my $region_property = {
    type        => 'string',
    description => 'Server region of the schedule (default: europe). Each region has its own schedule; "all" returns every region, each event with its region.',
    enum        => [@REGIONS],
  };

  # Tool: get_event_timers
  $server->tool(
    name        => 'get_event_timers',
    description => 'Get current event schedules and timers. Shows which events are active now and when they start/end. Data is cached and refreshes hourly.',
    input_schema => {
      type       => 'object',
      properties => {
        region => $region_property,
      },
    },
    code => sub {
      my ($tool, $args) = @_;
      my $events = $self->_events(region => $args->{region});
      my @results = map { $self->_event_to_hash($_) } @$events;
      return $self->_to_json(\@results);
    },
  );

  # Tool: get_active_events
  $server->tool(
    name        => 'get_active_events',
    description => 'Get only currently active events right now.',
    input_schema => {
      type       => 'object',
      properties => {
        region => $region_property,
      },
    },
    code => sub {
      my ($tool, $args) = @_;
      my $events = $self->_events(region => $args->{region});
      my @active = grep { $_->is_active_now } @$events;

      return "No events are currently active" unless @active;

      my @results = map { $self->_event_to_hash($_) } @active;
      return $self->_to_json(\@results);
    },
  );

  # Tool: get_map_data
  $server->tool(
    name        => 'get_map_data',
    description => 'Get map marker data for a specific map. Requires a category filter to limit results. Use list_maps to see available maps.',
    input_schema => {
      type       => 'object',
      properties => {
        map => {
          type        => 'string',
          description => 'Map id as listed by list_maps',
          enum        => [$self->api->maps],
        },
        category => {
          type        => 'string',
          description => 'Category to filter by (required)',
          enum        => [qw(arc containers locations events nature quests)],
        },
        subcategory => {
          type        => 'string',
          description => 'Subcategory filter (e.g., "tick", "extraction", "base_container")',
        },
        search => {
          type        => 'string',
          description => 'Search term to filter marker names and subcategories (case-insensitive)',
        },
      },
      required => ['map', 'category'],
    },
    code => sub {
      my ($tool, $args) = @_;
      my $markers = $self->api->map_data(map => $args->{map});

      return "No map data found for '$args->{map}'" unless $markers && @$markers;

      my $filtered = $self->_filter_markers($markers, %$args{qw(category subcategory search)});

      return "No markers found matching criteria" unless @$filtered;

      my @results = map { $self->_marker_to_hash($_) } @$filtered;

      return $self->_to_json(\@results);
    },
  );

  # Tool: list_maps
  $server->tool(
    name        => 'list_maps',
    description => 'List all available maps in ARC Raiders.',
    input_schema => {
      type       => 'object',
      properties => {},
    },
    code => sub {
      my ($tool, $args) = @_;
      my %names = $self->api->map_display_names;
      my @maps = map { { id => $_, name => $names{$_} } } $self->api->maps;
      return $self->_to_json(\@maps);
    },
  );

  # Tool: get_ermal
  $server->tool(
    name        => 'get_ermal',
    description => 'Get Ermal: this week\'s offers (item, coin cost, offer period, the items he accepts as payment) and his permanent services such as the Expedition Vault and the Stash Expansion.',
    input_schema => {
      type       => 'object',
      properties => {},
    },
    code => sub {
      my ($tool, $args) = @_;
      my $ermal = $self->_ermal_result;

      return "No offers from Ermal found" unless $ermal;
      return $self->_to_json($ermal);
    },
  );

  # Tool: get_hideout
  $server->tool(
    name        => 'get_hideout',
    description => 'Get the hideout stations with their upgrade levels: for each level the items it needs (item id and quantity), unlock requirements and the crafts it opens.',
    input_schema => {
      type       => 'object',
      properties => {
        station => {
          type        => 'string',
          description => 'Station id or name (e.g., "weapon-bench", "Gunsmith"); all stations when left out',
        },
        level => {
          type        => 'integer',
          description => 'Only this upgrade level',
          minimum     => 1,
        },
      },
    },
    code => sub {
      my ($tool, $args) = @_;
      my ($stations, $message) = $self->_hideout_result(%$args{qw(station level)});

      return $message unless $stations;
      return $self->_to_json($stations);
    },
  );

  # Tool: get_weekly_trials
  $server->tool(
    name        => 'get_weekly_trials',
    description => 'Get the weekly trials: the ones running now and the coming ones, with the time window the answer is valid for (active_window_end, next_window_start).',
    input_schema => {
      type       => 'object',
      properties => {
        include_all => {
          type        => 'boolean',
          description => 'Also list the trials that are neither running nor coming (default: false)',
          default     => 0,
        },
      },
    },
    code => sub {
      my ($tool, $args) = @_;
      return $self->_to_json($self->_weekly_trials_result(include_all => $args->{include_all}));
    },
  );

  # Tool: calculate_requirements
  $server->tool(
    name        => 'calculate_requirements',
    description => 'Calculate what materials are needed to craft items. Can show direct requirements or recursively resolve to base (raw) materials that cannot be crafted further.',
    input_schema => {
      type       => 'object',
      properties => {
        items => {
          type        => 'array',
          description => 'List of items to calculate requirements for',
          items       => {
            type       => 'object',
            properties => {
              item  => { type => 'string', description => 'Item name' },
              count => { type => 'integer', description => 'Quantity needed', default => 1 },
            },
            required => ['item'],
          },
        },
        base_only => {
          type        => 'boolean',
          description => 'If true, recursively resolve to raw/base materials only (materials that cannot be crafted). Default: false (show direct requirements)',
          default     => 0,
        },
      },
      required => ['items'],
    },
    code => sub {
      my ($tool, $args) = @_;
      my $items = $args->{items} // [];
      my $base_only = $args->{base_only} // 0;

      my $result;
      if ($base_only) {
        $result = $self->api->calculate_base_requirements(items => $items);
      } else {
        $result = $self->api->calculate_requirements(items => $items);
      }

      my @requirements = map { $self->_requirement_to_hash($_) } @{$result->{requirements}};

      return $self->_to_json({
        requirements => \@requirements,
        missing      => $result->{missing},
      });
    },
  );

  return $server;
}

sub run_stdio {
  my ($self) = @_;
  $self = $self->new unless ref $self;
  $self->server->to_stdio;
}

1;

=head1 SYNOPSIS

  # As a stdio MCP server (for Claude Desktop, etc.)
  use MCP::ArcRaiders;
  MCP::ArcRaiders->new->run_stdio;

  # Or use the provided script:
  # mcp-arcraiders

  # In a Mojolicious app (combined MCP + REST):
  use Mojolicious::Lite;
  use MCP::ArcRaiders;

  my $mcp = MCP::ArcRaiders->new;
  any '/mcp' => $mcp->server->to_action;
  app->start;

  # With custom API (for testing):
  my $mcp = MCP::ArcRaiders->new(
    api => WWW::MetaForge::ArcRaiders->new(ua => $mock_ua),
  );

=head1 DESCRIPTION

MCP::ArcRaiders provides an MCP (Model Context Protocol) server that exposes
ARC Raiders game data to AI assistants like Claude. It wraps the
L<WWW::MetaForge::ArcRaiders> API in MCP tools.

The distribution also includes C<mcp-arcraiders-http>, a combined HTTP server
that provides both MCP protocol support and a REST API for integration with
ChatGPT and other AI assistants.

=head1 DATA SOURCE

All game data comes from L<MetaForge|https://metaforge.app/arc-raiders>
(L<https://metaforge.app/arc-raiders>) through L<WWW::MetaForge::ArcRaiders>.
The MetaForge terms ask public projects to name the source with a link to
that address; the server does so in its MCP server instructions and in the
C<info> of the OpenAPI description, and so should every page or answer built
on it.

=attr api

L<WWW::MetaForge::ArcRaiders> instance. Can be injected for testing.

=attr cache

L<WWW::MetaForge::Cache> instance with namespace C<mcp-arcraiders>.

=attr json

L<JSON::MaybeXS> instance for JSON encoding. Pretty printing, canonical ordering and blessed conversion. It returns character strings (no C<utf8>): the MCP framework encodes the response to UTF-8 once.

=attr server

L<MCP::Server> instance with all tools registered.

=method run_stdio

  $mcp->run_stdio;
  # or as class method:
  MCP::ArcRaiders->run_stdio;

Run the MCP server over stdio.

=head1 AVAILABLE TOOLS

All tools are available via MCP protocol and as REST endpoints.

=head2 search_items

Search for items by name or keyword.

B<Parameters:>

=over

=item * C<search> (string) - Search term (e.g., "Ferro", "weapon", "medkit")

=item * C<limit> (integer, default: 20) - Maximum number of results

=back

B<REST:> C<GET /api/items?search=ferro&limit=10>

=head2 get_item_details

Get full details about an item: crafting components, recycle yield, sellers, what it is used in, which items recycle into it, which ARCs drop it, its mods and where it is found.

B<Parameters:>

=over

=item * C<name> (string, required) - Exact or partial item name

=back

B<REST:> C<GET /api/items/:name>

=head2 get_arcs

Get ARCs with their loot drops and their data (variants, e.g. whether a variant flies).

B<Parameters:>

=over

=item * C<include_loot> (boolean, default: true) - Include loot drop information

=back

B<REST:> C<GET /api/arcs>

=head2 get_quests

Get an overview of all quests over all pages of the API: id, name, trader,
XP and the number of required items and rewards. The API has no quest type,
so there is no type filter.

B<Parameters:>

=over

=item * C<trader> (string, optional) - Only this trader's quests (exact name, case-insensitive)

=item * C<name> (string, optional) - Only quests whose name contains this text (case-insensitive)

=back

B<REST:> C<GET /api/quests?trader=Celeste&name=journals>

=head2 get_quest_details

Get one quest in full: description, objectives, required items, all rewards,
additional rewards and the manifest (prerequisites and objective graph).

B<Parameters:>

=over

=item * C<quest> (string, required) - Quest id or exact name (case-insensitive)

=back

B<REST:> C<GET /api/quests/:quest>

=head2 get_traders

Get all traders and their current inventory.

B<REST:> C<GET /api/traders>

=head2 find_item_seller

Find which traders sell a specific item, including Ermal's offers (with coin
cost, offer period and the items he accepts as payment).

B<REST:> C<GET /api/items/:name/sellers>

B<Parameters:>

=over

=item * C<item_name> (string, required) - Name of the item to find

=back

=head2 get_event_timers

Get event schedules with active status and countdown timers.
Data is cached and refreshes hourly.

B<Parameters:>

=over

=item * C<region> (string, enum: europe, north-america, oceania, east-asia, brazil, all; default: europe) - Server region of the schedule. With C<all> every event carries its region.

=back

B<REST:> C<GET /api/events?region=north-america>

=head2 get_active_events

Get only currently active events. Takes the same C<region> parameter.

B<REST:> C<GET /api/events/active?region=north-america>

=head2 get_map_data

Get map markers/POIs for a specific map. Requires a category filter to
limit response size (maps can have 500+ markers).

B<Parameters:>

=over

=item * C<map> (string, required) - Map id as listed by C<list_maps>; the choices follow L<WWW::MetaForge::ArcRaiders/maps>, so a new map needs no change here

=item * C<category> (string, required) - Category filter: arc, containers, locations, events, nature, quests

=item * C<subcategory> (string, optional) - Subcategory filter (e.g., "tick", "extraction", "weapon_case")

=item * C<search> (string, optional) - Search term for marker names and subcategories (case-insensitive)

=back

B<Categories and subcategories:>

=over

=item * B<arc> - Enemy spawns: tick, pop, bison, rocketeer, rollbot, sentinel, turret, queen, fireball, hornet, bastion, wasp

=item * B<containers> - Loot containers: base_container, ammo_crate, breachable_container, utility_crate, med_crate, weapon_case, arc_courier, arc_husk, locker, raider_cache, car, bag, basket

=item * B<locations> - Points of interest: player_spawn, field_depot, supply_station, raider_camp, extraction, locked_room, hatch

=item * B<events> - Dynamic events: harvester

=item * B<nature> - Gatherable plants (e.g. candleberries)

=item * B<quests> - Quest locations (the subcategory is the quest id)

=back

B<REST:> C<GET /api/maps/:map?category=containers&subcategory=weapon_case&search=north>

B<Examples:>

  # Get all extraction points on Dam
  GET /api/maps/dam?category=locations&subcategory=extraction

  # Get all weapon cases on Spaceport
  GET /api/maps/spaceport?category=containers&subcategory=weapon_case

  # Get all Tick spawns on Buried City
  GET /api/maps/buried-city?category=arc&subcategory=tick

=head2 list_maps

List all available maps with display names.

B<REST:> C<GET /api/maps>

=head2 calculate_requirements

Calculate crafting materials needed for items.

B<Parameters:>

=over

=item * C<items> (array, required) - List of items: [{item: "Item Name", count: 1}, ...]

=item * C<base_only> (boolean, default: false) - If true, recursively resolve to raw/base materials only

=back

B<REST:> C<POST /api/requirements> with JSON body

B<Example:>

  POST /api/requirements
  {"items": [{"item": "Advanced Medkit", "count": 5}], "base_only": true}

=head2 get_ermal

Get Ermal: this week's offers (item, coin cost, offer period and the items he
accepts as payment) and his permanent services (Expedition Vault, Stash
Expansion).

B<REST:> C<GET /api/ermal>

=head2 get_hideout

Get the hideout stations with their upgrade levels: for each level the items
it needs (item id and quantity), the unlock requirements and the crafts it
opens.

B<Parameters:>

=over

=item * C<station> (string, optional) - Station id or name (C<weapon-bench>, C<Gunsmith>); all stations when left out

=item * C<level> (integer, optional) - Only this upgrade level

=back

B<REST:> C<GET /api/hideout?station=weapon-bench&level=2>

=head2 get_weekly_trials

Get the weekly trials running now and the coming ones, with the time window
the answer is valid for: C<window.active_window_end> and
C<window.next_window_start>. The list is cached and refreshes when the first
of the two boundaries has passed.

B<Parameters:>

=over

=item * C<include_all> (boolean, default: false) - Also list the trials that are neither running nor coming

=back

B<REST:> C<GET /api/weekly-trials?include_all=1>

=head1 CHATGPT INTEGRATION

The HTTP server (C<mcp-arcraiders-http>) provides an OpenAPI specification
at C</openapi.json> for ChatGPT Actions integration.

B<Setup:>

=over

=item 1. Deploy the HTTP server (e.g., via Docker)

=item 2. In ChatGPT, create a new GPT or edit an existing one

=item 3. Add an Action and import the schema from C<https://your-server/openapi.json>

=item 4. ChatGPT can now query ARC Raiders game data

=back

B<Environment variables:>

=over

=item * C<OPENAPI_SERVER_URL> - Override the server URL in the OpenAPI spec

=back

=head1 CLAUDE DESKTOP INTEGRATION

For Claude Desktop, add to your MCP configuration:

  {
    "mcpServers": {
      "arcraiders": {
        "command": "mcp-arcraiders"
      }
    }
  }

Or for the HTTP variant:

  {
    "mcpServers": {
      "arcraiders": {
        "url": "https://your-server/mcp"
      }
    }
  }

=head1 SEE ALSO

L<MCP>, L<MCP::Server>, L<WWW::MetaForge::ArcRaiders>

Game data: L<MetaForge|https://metaforge.app/arc-raiders>, L<https://metaforge.app/arc-raiders>

=cut
