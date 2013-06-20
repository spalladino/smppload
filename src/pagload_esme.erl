-module(pagload_esme).
-behaviour(gen_esme).

%% API
-export([
	start_link/0,
	start/0,
	stop/0,

	connect/2,

	bind_transmitter/1,
	bind_receiver/1,
	bind_transceiver/1,
	unbind/0,

	submit_sm/4,

	get_avg_rps/0,
	get_rps/0,
	set_max_rps/1
]).

%% gen_esme callbacks
-export([
	handle_accept/3,
	handle_alert_notification/2,
	handle_closed/2,
	handle_data_sm/3,
	handle_deliver_sm/3,
	handle_outbind/2,
	handle_req/4,
	handle_resp/3,
	handle_unbind/3
]).

%% gen_server callbacks
-export([
	init/1,
	handle_call/3,
	handle_cast/2,
	handle_info/2,
	terminate/2,
	code_change/3
]).

-include("pagload.hrl").
-include_lib("oserl/include/oserl.hrl").
-include_lib("oserl/include/smpp_globals.hrl").

-define(HIGH, 0).
-define(LOW, 10).

-define(BIND_TIMEOUT, 30000).
-define(UNBIND_TIMEOUT, 30000).
-define(SUBMIT_TIMEOUT, 120000).
-define(DELIVERY_TIMEOUT, 100000).

-record(state, {
	bind_from,
	bind_ref,
	bind_req,

	unbind_from,
	unbind_ref,
	unbind_req,

	submit_reqs = [],
	delivery_reqs = []
}).

%% ===================================================================
%% API
%% ===================================================================

start_link() ->
	Opts = [], %[{rps, 1}, {file_queue, "./sample_esme.dqueue"}],
	gen_esme:start_link({local, ?MODULE}, ?MODULE, [], Opts).

start() ->
	Opts = [],
	gen_esme:start({local, ?MODULE}, ?MODULE, [], Opts).

stop() ->
	gen_esme:cast(?MODULE, stop).

connect(Host, Port) ->
	gen_esme:open(?MODULE, Host, [{port, Port}]).

bind_transmitter(Params) ->
	gen_esme:call(?MODULE, {bind_transmitter, Params}, ?BIND_TIMEOUT).

bind_receiver(Params) ->
	gen_esme:call(?MODULE, {bind_receiver, Params}, ?BIND_TIMEOUT).

bind_transceiver(Params) ->
	gen_esme:call(?MODULE, {bind_transceiver, Params}, ?BIND_TIMEOUT).

unbind() ->
	gen_esme:call(?MODULE, {unbind, []}, ?UNBIND_TIMEOUT).

submit_sm(Source, Destination, Body, Opts) ->
	Params0 = [
		%{source_addr_ton, ?TON_ALPHANUMERIC},
		%{source_addr_npi, ?NPI_UNKNOWN},
		{source_addr_ton, ?TON_INTERNATIONAL},
		{source_addr_npi, ?NPI_ISDN},
		{source_addr, Source},

		{dest_addr_ton, ?TON_INTERNATIONAL},
		{dest_addr_npi, ?NPI_ISDN},
		{destination_addr, Destination}
	],
    Priority = ?gv(priority, Opts, ?LOW),
	RegDlr = ?gv(registered_delivery, Opts, 0),
	Params1 = [{registered_delivery, RegDlr} | Params0],
	Params2 = [{short_message, Body} | Params1],
    %submit(Body, Params1, [], Priority)
	gen_esme:call(?MODULE, {submit_sm, Params2, [], Priority}, ?SUBMIT_TIMEOUT).

get_avg_rps() ->
    gen_esme:rps_avg(?MODULE).

get_rps() ->
    gen_esme:rps(?MODULE).

set_max_rps(Rps) ->
    gen_esme:rps_max(?MODULE, Rps).

%% ===================================================================
%% gen_server callbacks
%% ===================================================================

init([]) ->
    {ok, #state{}}.

handle_call({bind_transmitter, Params}, From, State) ->
	gen_esme:bind_transmitter(?MODULE, Params, []),
	{noreply, State#state{bind_from = From, bind_req = {bind_transmitter, Params}}};
handle_call({bind_receiver, Params}, From, State) ->
	gen_esme:bind_receiver(?MODULE, Params, []),
	{noreply, State#state{bind_from = From, bind_req = {bind_receiver, Params}}};
handle_call({bind_transceiver, Params}, From, State) ->
	gen_esme:bind_transceiver(?MODULE, Params, []),
	{noreply, State#state{bind_from = From, bind_req = {bind_transceiver, Params}}};
handle_call({unbind, Params}, From, State) ->
	gen_esme:unbind(?MODULE, Params),
	{noreply, State#state{unbind_from = From, unbind_req = {unbind, Params}}};
handle_call({submit_sm, Params, Args, Priority}, From, State) ->
	gen_esme:queue_submit_sm(?MODULE, Params, Args, Priority),
	Req = {submit_sm, Params},
	{noreply, State#state{submit_reqs = [{Req, From, undefined, undefined} | State#state.submit_reqs]}}.

handle_cast(stop, State) ->
	gen_esme:close(?MODULE),
	{noreply, State}.

handle_info({timeout, TimerRef, ReqRef}, State) ->
	SubmitReqs0 = State#state.submit_reqs,
	DeliveryReqs0 = State#state.delivery_reqs,

	%% find timeouted delivery request.
	{{Req, From, ReqRef, OutMsgId}, SubmitReqs1} =
		cl_lists:keyextract(ReqRef, 3, SubmitReqs0),
	{{ReqRef, TimerRef}, DeliveryReqs1} =
			cl_lists:keyextract(ReqRef, 1, DeliveryReqs0),
	?WARN("Request: ~p~n", [Req]),
	?WARN("Delivery timeout~n", []),

	%% reply to caller.
	gen_esme:reply(From, {ok, OutMsgId, delivery_timeout}),

	{noreply, State#state{
		submit_reqs = SubmitReqs1,
		delivery_reqs = DeliveryReqs1
	}};
handle_info(Info, State) ->
	?WARN("Info: ~p~n", [Info]),
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ===================================================================
%% gen_esme callbacks
%% ===================================================================

handle_req({bind_transmitter, _Params}, _Args, ReqRef, State) ->
	{noreply, State#state{bind_ref = ReqRef}};
handle_req({bind_receiver, _Params}, _Args, ReqRef, State) ->
	{noreply, State#state{bind_ref = ReqRef}};
handle_req({bind_transceiver, _Params}, _Args, ReqRef, State) ->
	{noreply, State#state{bind_ref = ReqRef}};
handle_req({unbind, _Params}, _Args, ReqRef, State) ->
	{noreply, State#state{unbind_ref = ReqRef}};
handle_req(Req, Args, ReqRef, State) ->
	{{Req, From, undefined, undefined}, Reqs} =
		cl_lists:keyextract(Req, 1, State#state.submit_reqs),
	{noreply, State#state{submit_reqs = [{Req, From, ReqRef, undefined} | Reqs]}}.

handle_resp({ok, PduResp}, ReqRef, State = #state{
	bind_from = From,
	bind_ref = ReqRef,
	bind_req = Req
}) ->
	?DEBUG("Request: ~p~n", [Req]),
	?DEBUG("Response: ~p~n", [prettify_pdu(PduResp)]),
	SystemId = smpp_operation:get_value(system_id, PduResp),
	gen_esme:reply(From, {ok, SystemId}),
	gen_esme:resume(?MODULE),
	{noreply, State#state{
		bind_from = undefined,
		bind_ref = undefined,
		bind_req = undefined,
		submit_reqs = []
	}};
handle_resp({ok, PduResp}, ReqRef, State = #state{
	unbind_from = From,
	unbind_ref = ReqRef,
	unbind_req = Req
}) ->
	?DEBUG("Request: ~p~n", [Req]),
	?DEBUG("Response: ~p~n", [prettify_pdu(PduResp)]),
	gen_esme:reply(From, ok),
	{noreply, State#state{
		unbind_from = undefined,
		unbind_ref = undefined,
		unbind_req = undefined,
		submit_reqs = [],
		delivery_reqs = []
	}};
handle_resp({error, {command_status, Status}}, ReqRef, State = #state{
	bind_from = From,
	bind_ref = ReqRef,
	bind_req = Req
}) ->
	?DEBUG("Request: ~p~n", [Req]),
	?DEBUG("Bind failed with: ~p~n", [Status]),
	gen_esme:reply(From, {error, smpp_error:format(Status)}),
	gen_esme:close(?MODULE),
	{noreply, State#state{
		bind_from = undefined,
		bind_ref = undefined,
		bind_req = undefined
	}};
handle_resp({error, {command_status, Status}}, ReqRef, State = #state{
	unbind_from = From,
	unbind_ref = ReqRef,
	unbind_req = Req
}) ->
	?DEBUG("Request: ~p~n", [Req]),
	?DEBUG("Bind failed with: ~p~n", [Status]),
	Reason = smpp_error:format(Status),
	gen_esme:close(?MODULE),
	gen_esme:reply(From, {error, Reason}),
	{noreply, State#state{
		unbind_from = undefined,
		unbind_ref = undefined,
		unbind_req = undefined
	}};
handle_resp({ok, PduResp}, ReqRef, State) ->
	{{Req, From, ReqRef, undefined}, Reqs} =
		cl_lists:keyextract(ReqRef, 3, State#state.submit_reqs),
	?DEBUG("Request: ~p~n", [Req]),
	?DEBUG("Response: ~p~n", [prettify_pdu(PduResp)]),

	OutMsgId = smpp_operation:get_value(message_id, PduResp),

	{_, Params} = Req,
	State1 =
		case ?gv(registered_delivery, Params, 0) of
			0 ->
				gen_esme:reply(From, {ok, OutMsgId, no_delivery}),
				State#state{submit_reqs = Reqs};
			1 ->
				%% start wait for delivery timer.
				TimerRef = erlang:start_timer(?DELIVERY_TIMEOUT, self(), ReqRef),
				State#state{
					submit_reqs = [{Req, From, ReqRef, OutMsgId} | Reqs],
					delivery_reqs = [{ReqRef, TimerRef} | State#state.delivery_reqs]
				}
		end,
	{noreply, State1};
handle_resp({error, {command_status, Status}}, ReqRef, State) ->
	{{Req, From, ReqRef, undefined}, Reqs} =
		cl_lists:keyextract(ReqRef, 3, State#state.submit_reqs),
	?DEBUG("Request: ~p~n", [Req]),
	?DEBUG("Failed with: ~p~n", [Status]),
	gen_esme:reply(From, {error, smpp_error:format(Status)}),
	{noreply, State#state{submit_reqs = Reqs}}.

handle_deliver_sm(PduDlr, _From, State0) ->
	?DEBUG("Deliver: ~p~n", [prettify_pdu(PduDlr)]),
	{?COMMAND_ID_DELIVER_SM, 0, _SeqNum, Body} = PduDlr,
	EsmClass = smpp_operation:get_value(esm_class, PduDlr),
	IsReceipt =
		EsmClass band ?ESM_CLASS_TYPE_MC_DELIVERY_RECEIPT =:=
			?ESM_CLASS_TYPE_MC_DELIVERY_RECEIPT,
	{Reply, State1}  =
		case IsReceipt of
			true ->
				handle_receipt(Body, State0);
			false ->
				handle_message(Body, State0)
	end,
	{reply, Reply, State1}.

handle_closed(Reason, State) ->
	?DEBUG("Session closed with: ~p~n", [Reason]),
	{stop, Reason, State}.

handle_unbind(_Pdu, _From, State) ->
	?WARN("Unbind~n", []),
    {reply, ok, State}.

handle_outbind(Pdu, State) ->
	erlang:error(function_clause, [Pdu, State]).

handle_data_sm(Pdu, From, State) ->
    erlang:error(function_clause, [Pdu, From, State]).

handle_accept(Addr, From, State) ->
    erlang:error(function_clause, [Addr, From, State]).

handle_alert_notification(Pdu, State) ->
    erlang:error(function_clause, [Pdu, State]).

%% ===================================================================
%% Internal
%% ===================================================================

submit(Msg, Params, Args, Priority) when length(Msg) > ?SM_MAX_SIZE ->
    RefNum = smpp_ref_num:next(?MODULE),
    L = smpp_sm:split([{short_message, Msg} | Params], RefNum, udh),
    lists:foreach(fun(X) -> submit(X, Args, Priority) end, L);
submit(Msg, Params, Args, Priority) ->
    submit([{short_message, Msg} | Params], Args, Priority).

submit(Params, Args, Priority) ->
	gen_esme:queue_submit_sm(?MODULE, Params, Args, Priority).

handle_receipt(Body, State) ->
	?DEBUG("Receipt: ~p~n", [Body]),
	{OutMsgId, DlrState} = receipt_data(Body),
	SubmitReqs0 = State#state.submit_reqs,
	DeliveryReqs0 = State#state.delivery_reqs,
	{SubmitReqs2, DeliveryReqs2}  =
		case lists:keyfind(OutMsgId, 4, SubmitReqs0) of
			false ->
				?DEBUG("Ignored~n", []),
				{SubmitReqs0, DeliveryReqs0};
			_ ->
				%% process request.
				{{_Req, From, ReqRef, OutMsgId}, SubmitReqs1} =
					cl_lists:keyextract(OutMsgId, 4, SubmitReqs0),
				%% cancel wait for delivery timer.
				{{ReqRef, TimerRef}, DeliveryReqs1} =
					cl_lists:keyextract(ReqRef, 1, DeliveryReqs0),
				erlang:cancel_timer(TimerRef),
				%% reply to caller.
				gen_esme:reply(From, {ok, OutMsgId, DlrState}),
				?DEBUG("Processed~n", []),
				{SubmitReqs1, DeliveryReqs1}
		end,
	{{ok, []}, State#state{
		submit_reqs = SubmitReqs2,
		delivery_reqs = DeliveryReqs2
	}}.

handle_message(Body, State) ->
	?WARN("Message: ~p~n", [Body]),
	{{ok, []}, State}.

receipt_data(Body) ->
    case receipt_data_from_tlv(Body) of
        false -> receipt_data_from_text(Body);
        Data  -> Data
    end.

receipt_data_from_tlv(Body) ->
	ID = ?gv(receipted_message_id, Body),
	State = ?gv(message_state, Body),
	case ID =/= undefined andalso State =/= undefined of
		true  -> {ID, State};
		false -> false
	end.

receipt_data_from_text(Body) ->
	Text = ?gv(short_message, Body),
	Opts = [caseless, {capture, all_but_first, list}],
	{match, [ID]} = re:run(Text, "id:([[:xdigit:]]+)", Opts),
	{match, [State]} = re:run(Text, "stat:(\\w+)", Opts),
	{ID, State}.

prettify_pdu({CmdId, Status, SeqNum, Body}) ->
	case CmdId of
		?COMMAND_ID_DELIVER_SM ->
			{deliver_sm, Status, SeqNum, Body};
		?COMMAND_ID_SUBMIT_SM_RESP ->
			{submit_sm_resp, Status, SeqNum, Body};
		?COMMAND_ID_BIND_RECEIVER_RESP ->
			{bind_receiver_resp, Status, SeqNum, Body};
		?COMMAND_ID_BIND_TRANSMITTER_RESP ->
			{bind_transmitter_resp, Status, SeqNum, Body};
		?COMMAND_ID_BIND_TRANSCEIVER_RESP ->
			{bind_transceiver_resp, Status, SeqNum, Body};
		?COMMAND_ID_UNBIND_RESP ->
			{unbind_resp, Status, SeqNum, Body};
		_ ->
			{CmdId, Status, SeqNum, Body}
	end.