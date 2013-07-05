-ifndef(message_hrl).
-define(message_hrl, 1).

%% 140 chars for Latin 1 encoding.
-define(MAX_MSG_LEN, 140).
-define(MAX_SEG_LEN, 134).

-record(address, {
	addr :: binary(),
	ton  :: pos_integer(),
	npi  :: pos_integer()
}).

-record(message, {
	source :: #address{},
	destination :: #address{},
	body :: binary(),
	esm_class = 0 :: integer(),
	delivery :: boolean()
}).

-endif.
