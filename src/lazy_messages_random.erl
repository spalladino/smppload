-module(lazy_messages_random).

-behaviour(lazy_messages).

-export([
	init/1,
	deinit/1,
	get_next/1
]).

-include("lazy_messages.hrl").
-include("message.hrl").

-ifdef(TEST).
   -include_lib("eunit/include/eunit.hrl").
-endif.

-record(state, {
	seed,
	source,
	destination,
	count,
	length,
	delivery
}).

%% ===================================================================
%% API
%% ===================================================================

-spec init(config()) -> state().
init(Config) ->
	Seed = proplists:get_value(seed, Config, now()),
	Source = parser:parse_address(proplists:get_value(source, Config)),
	Destination = parser:parse_address(proplists:get_value(destination, Config)),
	Count = proplists:get_value(count, Config),
	Length = proplists:get_value(length, Config),
	Delivery = proplists:get_value(delivery, Config),
	{ok, #state{
		seed = Seed,
		source = Source,
		destination = Destination,
		count = Count,
		length = Length,
		delivery = Delivery
	}}.

-spec deinit(state()) -> ok.
deinit(_State) ->
	ok.

-spec get_next(state()) -> {ok, #message{}, state()} | {no_more, state()}.
get_next(State = #state{count = Count}) when Count =< 0 ->
	{no_more, State};
get_next(State = #state{
	seed = Seed0,
	source = Source,
	destination = Destination,
	count = Count,
	length = Length,
	delivery = Delivery
}) ->
	{Body, Seed1}  = build_random_body(Length, Seed0),
	Message = #message{
		source = Source,
		destination = Destination,
		body = Body,
		delivery = Delivery
	},
	{ok, Message, State#state{seed = Seed1, count = Count - 1}}.

%% ===================================================================
%% Internal
%% ===================================================================

build_random_body(Length, Seed) ->
	build_random_body(Length, "", Seed).

build_random_body(Length, Body, Seed) when length(Body) =:= Length ->
	{Body, Seed};
build_random_body(Length, Body, Seed0) ->
	{R, Seed1} = random:uniform_s($z, Seed0),
	if
		(R >= $0 andalso R =< $9) orelse
		(R >= $A andalso R =< $Z) orelse
		(R >= $a andalso R =< $z) ->
			build_random_body(Length, [R | Body], Seed1);
		true ->
			build_random_body(Length, Body, Seed1)
	end.

%% ===================================================================
%% Tests begin
%% ===================================================================

-ifdef(TEST).

one_test() ->
	Config = [{seed, {1,1,1}}, {source, "s"}, {destination, "d"}, {delivery, true}, {count, 3}, {length, 5}],
	{ok, State0} = lazy_messages_random:init(Config),
	{ok, Msg, State1} = lazy_messages_random:get_next(State0),
	#message{source = Source, destination = Destination, body = Body1, delivery = Delivery} = Msg,
	?assertEqual(#address{addr = "s", ton = 1, npi = 1}, Source),
	?assertEqual(#address{addr = "d", ton = 1, npi = 1}, Destination),
	?assert(Delivery),
	?assertEqual("Plesn", Body1),
	{ok, #message{body = Body2}, State2} = lazy_messages_random:get_next(State1),
	?assertEqual("YPTRt", Body2),
	{ok, #message{body = Body3}, State3} = lazy_messages_random:get_next(State2),
	?assertEqual("4rIYy", Body3),
	{no_more, State4} = lazy_messages_random:get_next(State3),
	ok = lazy_messages_random:deinit(State4).

-endif.

%% ===================================================================
%% Tests end
%% ===================================================================
