%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at http://mozilla.org/MPL/2.0/.
%%% @author Seventh State <contact@seventhstate.io>
%%% @copyright (C) 2025, Erlang Solutions Ltd., Seventh State

%% Macros for logging with module prefix
-define(LOG(Level, Fmt, Args), logger:Level("[~s] " ++ Fmt, [?MODULE | Args])).

-define(DBG(Fmt, Args), ?LOG(debug, Fmt, Args)).
-define(INF(Fmt, Args), ?LOG(info, Fmt, Args)).
-define(WRN(Fmt, Args), ?LOG(warning, Fmt, Args)).
-define(ERR(Fmt, Args), ?LOG(error, Fmt, Args)).

