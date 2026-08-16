package MCP::ArcRaiders;
# ABSTRACT: MCP Server providing ARC Raiders game data for AI assistants

use Moo;
use MCP::Server;
use WWW::MetaForge::ArcRaiders;
use WWW::MetaForge::Cache;
use JSON::MaybeXS;
use namespace::clean;

our $VERSION = '0.001';

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
  default => sub { JSON::MaybeXS->new(utf8 => 1, pretty => 1, canonical => 1, convert_blessed => 1) },
);

has server => (
  is      => 'ro',
  lazy    => 1,
  builder => '_build_server',
);

sub _build_cache {
  my ($self) = @_;
  return WWW::MetaForge::Cache->new(namespace => 'mcp-arcraiders');
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
    category    => $item->category,
    rarity      => $item->rarity,
    description => $item->description,
    weight      => $item->weight,
    stack_size  => $item->stack_size,
    base_value  => $item->base_value,
    stats       => $item->stats,
  };
}

sub _arc_to_hash {
  my ($self, $arc) = @_;
  return {
    id          => $arc->id,
    name        => $arc->name,
    type        => $arc->type,
    description => $arc->description,
    maps        => $arc->maps,
    duration    => $arc->duration,
    cooldown    => $arc->cooldown,
    loot        => $arc->loot,
    xp_reward   => $arc->xp_reward,
    coin_reward => $arc->coin_reward,
  };
}

sub _quest_to_hash {
  my ($self, $quest) = @_;
  return {
    id                => $quest->id,
    name              => $quest->name,
    type              => $quest->type,
    description       => $quest->description,
    objectives        => $quest->objectives,
    required_items    => $quest->required_items,
    rewards           => $quest->rewards,
    xp_reward         => $quest->xp_reward,
    reputation_reward => $quest->reputation_reward,
  };
}

sub _trader_to_hash {
  my ($self, $trader) = @_;
  return {
    name        => $trader->name,
    description => $trader->description,
    location    => $trader->location,
    inventory   => $trader->inventory,
  };
}

sub _event_to_hash {
  my ($self, $event) = @_;
  return {
    name             => $event->name,
    map              => $event->map,
    description      => $event->description,
    times            => $event->times,
    days             => $event->days,
    is_active_now    => $event->is_active_now ? \1 : \0,
    time_until_start => $event->time_until_start,
    time_until_end   => $event->time_until_end,
  };
}

sub _build_server {
  my ($self) = @_;

  my $server = MCP::Server->new(
    name    => 'arcraiders',
    version => $VERSION,
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
    description => 'Get detailed information about a specific item including crafting requirements, who sells it, and what it\'s used for.',
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
      my $items = $self->api->items(search => $args->{name}, limit => 5);

      return "No items found matching '$args->{name}'" unless @$items;

      my @details = map {
        {
          id                    => $_->id,
          name                  => $_->name,
          category              => $_->category,
          rarity                => $_->rarity,
          description           => $_->description,
          weight                => $_->weight,
          stack_size            => $_->stack_size,
          base_value            => $_->base_value,
          stats                 => $_->stats,
          crafting_requirements => $_->crafting_requirements,
          sold_by               => $_->sold_by,
          used_in               => $_->used_in,
          compatible_with       => $_->compatible_with,
          recycle_yield         => $_->recycle_yield,
        }
      } @$items;

      return $self->_to_json(\@details);
    },
  );

  # Tool: get_arcs
  $server->tool(
    name        => 'get_arcs',
    description => 'Get ARC missions/events in the game. ARCs are time-limited events that spawn on maps with specific loot.',
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
    description => 'Get quest information including objectives, requirements, and rewards.',
    input_schema => {
      type       => 'object',
      properties => {
        type => {
          type        => 'string',
          description => 'Filter by quest type (e.g., "StoryQuest", "SideQuest")',
          enum        => ['StoryQuest', 'SideQuest'],
        },
      },
    },
    code => sub {
      my ($tool, $args) = @_;
      my %params;
      $params{type} = $args->{type} if $args->{type};

      my $quests = $self->api->quests(%params);
      my @results = map { $self->_quest_to_hash($_) } @$quests;
      return $self->_to_json(\@results);
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
    description => 'Find which traders sell a specific item.',
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
      my $traders = $self->api->traders;

      my @sellers;
      for my $trader (@$traders) {
        if (my $item = $trader->find_item($item_name)) {
          push @sellers, {
            trader => $trader->name,
            item   => $item,
          };
        }
      }

      return "No traders found selling '$item_name'" unless @sellers;
      return $self->_to_json(\@sellers);
    },
  );

  # Tool: get_event_timers
  $server->tool(
    name        => 'get_event_timers',
    description => 'Get current event schedules and timers. Shows which events are active now and when they start/end. Data is cached and refreshes hourly.',
    input_schema => {
      type       => 'object',
      properties => {},
    },
    code => sub {
      my ($tool, $args) = @_;
      my $events = $self->api->event_timers_hourly;
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
      properties => {},
    },
    code => sub {
      my ($tool, $args) = @_;
      my $events = $self->api->event_timers_hourly;
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
          description => 'Map name',
          enum        => [qw(dam spaceport buried-city blue-gate stella-montis)],
        },
        category => {
          type        => 'string',
          description => 'Category to filter by (required)',
          enum        => [qw(arc containers locations events)],
        },
        subcategory => {
          type        => 'string',
          description => 'Subcategory filter (e.g., "tick", "extraction", "base_container")',
        },
        search => {
          type        => 'string',
          description => 'Search term to filter marker names (case-insensitive)',
        },
      },
      required => ['map', 'category'],
    },
    code => sub {
      my ($tool, $args) = @_;
      my $markers = $self->api->map_data(map => $args->{map});

      return "No map data found for '$args->{map}'" unless $markers && @$markers;

      # Filter by category (required)
      my @filtered = grep { $_->category eq $args->{category} } @$markers;

      # Filter by subcategory (optional)
      if ($args->{subcategory}) {
        @filtered = grep { $_->subcategory && $_->subcategory eq $args->{subcategory} } @filtered;
      }

      # Filter by search term (optional, case-insensitive)
      if ($args->{search}) {
        my $search = lc($args->{search});
        @filtered = grep {
          (defined $_->name && index(lc($_->name), $search) >= 0) ||
          (defined $_->description && index(lc($_->description), $search) >= 0)
        } @filtered;
      }

      return "No markers found matching criteria" unless @filtered;

      my @results = map {
        {
          name        => $_->name,
          type        => $_->type,
          category    => $_->category,
          subcategory => $_->subcategory,
          description => $_->description,
          x           => $_->x,
          y           => $_->y,
        }
      } @filtered;

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

      my @requirements = map {
        {
          item     => $_->{item}->name,
          id       => $_->{item}->id,
          count    => $_->{count},
          category => $_->{item}->category,
          rarity   => $_->{item}->rarity,
        }
      } @{$result->{requirements}};

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

=attr api

L<WWW::MetaForge::ArcRaiders> instance. Can be injected for testing.

=attr cache

L<WWW::MetaForge::Cache> instance with namespace C<mcp-arcraiders>.

=attr json

L<JSON::MaybeXS> instance for JSON encoding. Uses UTF-8 enabled, pretty printing, canonical ordering, and blessed conversion.

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

Get full details about an item including crafting requirements, sellers, and usage.

B<Parameters:>

=over

=item * C<name> (string, required) - Exact or partial item name

=back

B<REST:> C<GET /api/items/:name>

=head2 get_arcs

Get ARC missions/events with loot information.

B<Parameters:>

=over

=item * C<include_loot> (boolean, default: true) - Include loot drop information

=back

B<REST:> C<GET /api/arcs>

=head2 get_quests

Get quest information, optionally filtered by type.

B<Parameters:>

=over

=item * C<type> (string, enum: StoryQuest, SideQuest) - Filter by quest type

=back

B<REST:> C<GET /api/quests?type=SideQuest>

=head2 get_traders

Get all traders and their current inventory.

B<REST:> C<GET /api/traders>

=head2 find_item_seller

Find which traders sell a specific item.

B<Parameters:>

=over

=item * C<item_name> (string, required) - Name of the item to find

=back

=head2 get_event_timers

Get event schedules with active status and countdown timers.
Data is cached and refreshes hourly.

B<REST:> C<GET /api/events>

=head2 get_active_events

Get only currently active events.

B<REST:> C<GET /api/events/active>

=head2 get_map_data

Get map markers/POIs for a specific map. Requires a category filter to
limit response size (maps can have 500+ markers).

B<Parameters:>

=over

=item * C<map> (string, required) - Map name: dam, spaceport, buried-city, blue-gate, stella-montis

=item * C<category> (string, required) - Category filter: arc, containers, locations, events

=item * C<subcategory> (string, optional) - Subcategory filter (e.g., "tick", "extraction", "weapon_case")

=item * C<search> (string, optional) - Search term for marker names (case-insensitive)

=back

B<Categories and subcategories:>

=over

=item * B<arc> - Enemy spawns: tick, pop, bison, rocketeer, rollbot, sentinel, turret, queen, fireball, hornet, bastion, wasp

=item * B<containers> - Loot containers: base_container, ammo_crate, breachable_container, utility_crate, med_crate, weapon_case, arc_courier, arc_husk, locker, raider_cache, car, bag, basket

=item * B<locations> - Points of interest: player_spawn, field_depot, supply_station, raider_camp, extraction, locked_room, hatch

=item * B<events> - Dynamic events: harvester

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

MetaForge API: L<https://metaforge.app>

=cut
