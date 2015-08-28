-module(clj_analyzer).

-export([
         analyze/1,
         macroexpand/2,
         macroexpand_1/2,
         is_special/1
        ]).

-import(clj_core,
        ['symbol?'/1,
         first/1, second/1, third/1, fourth/1, rest/1,
         count/1,
         deref/1,
         name/1, namespace/1,
         meta/1,
         keyword/1, symbol/1,
         boolean/1,
         get/2,
         type/1]).

-spec is_special(any()) -> boolean().
is_special(S) ->
  lists:member(S, special_forms()).

-spec analyze(any()) -> clj_env:env().
analyze(Forms) ->
  Fun = fun(Form, Env) -> analyze(Env, Form) end,
  lists:foldl(Fun, clj_env:default(), Forms).

-spec macroexpand_1(clj_env:env(), 'clojerl.List':type()) -> any().
macroexpand_1(Env, Form) ->
  Op = first(Form),
  {MacroVar, Env} = lookup_var(Op, false, Env),
  case
    is_special(Op)
    orelse (not 'symbol?'(Op))
    orelse (MacroVar == undefined)
    orelse (not 'clojerl.Var':is_macro(MacroVar))
  of
    true -> Form;
    false ->
      {MacroVar, Env} = lookup_var(Op, false, Env),
      Fun = deref(MacroVar),
      Args = [Form, Env, rest(Form)],
      erlang:apply(Fun, Args)
  end.

-spec macroexpand(clj_env:env(), 'clojerl.List':type()) -> any().
macroexpand(Env, Form) ->
  case macroexpand_1(Env, Form) of
    Form -> {Form, Env};
    ExpandedForm -> macroexpand_1(Env, ExpandedForm)
  end.

%%------------------------------------------------------------------------------
%% Internal
%%------------------------------------------------------------------------------

-spec analyze(clj_env:env(), any()) -> clj_env:env().
analyze(Env, nil) ->
  Expr = erl_syntax:abstract(undefined),
  clj_env:push_expr(Env, Expr);
analyze(Env, Boolean) when is_boolean(Boolean) ->
  Expr = erl_syntax:abstract(Boolean),
  clj_env:push_expr(Env, Expr);
analyze(Env, String) when is_binary(String) ->
  Expr = erl_syntax:abstract(String),
  clj_env:push_expr(Env, Expr);
analyze(Env, Number) when is_number(Number) ->
  Expr = erl_syntax:abstract(Number),
  clj_env:push_expr(Env, Expr);
analyze(Env, Form) ->
  case type(Form) of
    'clojerl.Symbol' ->
      analyze_symbol(Env, Form);
    'clojerl.Keyword' ->
      Expr = erl_syntax:abstract(Form),
      clj_env:push_expr(Env, Expr);
    'clojerl.List' ->
      Op = first(Form),
      analyze_seq(Env, Op, Form);
    'clojerl.Vector' ->
      Expr = erl_syntax:abstract(Form),
      clj_env:push_expr(Env, Expr);
    'clojerl.Map' ->
      Expr = erl_syntax:abstract(Form),
      clj_env:push_expr(Env, Expr);
    'clojerl.Set' ->
      Expr = erl_syntax:abstract(Form),
      clj_env:push_expr(Env, Expr);
    _ ->
      throw({invalid_form, Form, Env})
  end.

-spec analyze_seq(clj_env:env(), any(), 'clojerl.List':type()) -> clj_env:env().
analyze_seq(_Env, undefined, _List) ->
  throw(<<"Can't call nil">>);
analyze_seq(Env, Op, List) ->
  case macroexpand_1(Env, List) of
    List ->
      case lists:member(Op, special_forms()) of
        true ->
          Name = name(Op),
          parse_special_form(Name, List, Env);
        false ->
          analyze_invoke(Env, List)
      end;
    ExpandedList ->
      analyze(Env, ExpandedList)
  end.

-spec parse_special_form(any(), 'clojerl.List':type(), clj_env:env()) -> clj_env:env().
parse_special_form(<<"def">>, List, Env) ->
  Docstring = validate_def_args(List),
  VarSymbol = second(List),
  case lookup_var(VarSymbol, Env) of
    {undefined, _} ->
      throw(<<"Can't refer to qualified var that doesn't exist">>);
    {Var, Env1} ->
      VarNsSym = 'clojerl.Var':namespace(Var),
      case {clj_env:current_ns(Env1), namespace(VarSymbol)} of
        {VarNsSym, _} -> ok;
        {_ , undefined} ->  throw(<<"Can't create defs outside of current ns">>);
        _ -> ok
      end,

      Meta = meta(VarSymbol),
      DynamicKeyword = keyword(<<"dynamic">>),
      IsDynamic = boolean(get(Meta, DynamicKeyword)),
      Var1 = 'clojerl.Var':dynamic(Var, IsDynamic),

      %% TODO: show warning when not dynamic but name suggests otherwise.
      %% TODO: Read metadata from symbol and add it to Var.

      Env2 = clj_env:update_var(Env1, Var1),
      Init = case Docstring of
               undefined -> third(List);
               _ -> fourth(List)
             end,
      {InitExpr, Env3} = clj_env:pop_expr(analyze(Env2, Init)),
      Expr = #{type => def,
               var => Var1,
               init => InitExpr},
      clj_env:push_expr(Env3, Expr)
  end.

-spec validate_def_args('clojerl.List':type()) -> undefined | binary().
validate_def_args(List) ->
  Docstring =
    case {count(List), third(List)} of
      {4, Str} when is_binary(Str) -> Str;
      _ -> undefined
    end,
  case type(second(List)) of
    'clojerl.Symbol' -> ok;
    _ -> throw(<<"First argument to def must be a Symbol">>)
  end,
  case count(List) of
    C when C == 2;
           C == 3, Docstring == undefined;
           C == 4, Docstring =/= undefined  ->
      Docstring;
    1 ->
      throw(<<"Too few arguments to def">>);
    _ ->
      throw(<<"Too many arguments to def">>)
  end.

-spec lookup_var('clojerl.Symbol':type(), clj_env:env()) -> ok.
lookup_var(VarSymbol, Env) ->
  lookup_var(VarSymbol, true, Env).

-spec lookup_var('clojerl.Symbol':type(),
                 CreateNew :: boolean(),
                 clj_env:env()) ->
  {'clojerl.Var':type(), clj_env:env()}.
lookup_var(VarSymbol, true, Env) ->
  NsSym = case namespace(VarSymbol) of
            undefined -> undefined;
            NsStr -> symbol(NsStr)
          end,

  case clj_env:current_ns(Env) of
    CurrentNs when CurrentNs == NsSym; NsSym == undefined ->
      NameSym = symbol(name(VarSymbol)),
      Fun = fun(Ns) -> clj_namespace:intern(Ns, NameSym) end,
      NewEnv = clj_env:update_ns(Env, CurrentNs, Fun),
      lookup_var(VarSymbol, false, NewEnv);
    _ ->
      {undefined, Env}
  end;
lookup_var(VarSymbol, false, Env) ->
  NsStr = namespace(VarSymbol),
  NameStr = name(VarSymbol),

  case {NsStr, NameStr} of
    {undefined, Name} when Name == <<"ns">>;
                           Name == <<"in-ns">> ->
      ClojureCoreSym = symbol(<<"clojure.core">>),
      Ns = clj_env:get_ns(Env, ClojureCoreSym),
      Var = clj_namespace:lookup(Ns, VarSymbol),
      {Var, Env};
    {undefined, _} ->
      CurrentNsSym = clj_env:current_ns(Env),
      Ns = clj_env:get_ns(Env, CurrentNsSym),
      Var = clj_namespace:lookup(Ns, VarSymbol),
      {Var, Env};
    {NsStr, NameStr} ->
      Ns = clj_env:get_ns(Env, symbol(NsStr)),
      Var = clj_namespace:lookup(Ns, symbol(NameStr)),
      {Var, Env}
  end.

special_forms() ->
  [symbol(<<"def">>),
   symbol(<<"loop*">>),
   symbol(<<"recur">>),
   symbol(<<"if">>),
   symbol(<<"case*">>),
   symbol(<<"let*">>),
   symbol(<<"letfn*">>),
   symbol(<<"do">>),
   symbol(<<"fn*">>),
   symbol(<<"quote">>),
   symbol(<<"var">>),
   symbol(<<"import*">>),
   symbol(<<"deftype*">>),
   symbol(<<"reify*">>),
   symbol(<<"try">>),
   %% symbol('monitor-enter') => fun analyze_def/2,
   %% symbol('monitor-exit') => fun analyze_def/2,
   %% symbol('new') => fun analyze_def/2,
   %% symbol('&') => fun analyze_def/2
   symbol(<<"throw">>),
   symbol(<<"catch">>),
   symbol(<<"finally">>)
  ].

-spec analyze_invoke(clj_env:env(), 'clojerl.List':type()) -> clj_env:env().
analyze_invoke(Env, Form) ->
  Env1 = analyze(Env, first(Form)),
  {_SymExpr, Env2} = clj_env:pop_expr(Env1),
  Env2.

-spec analyze_symbol(clj_env:env(), 'clojerl.Symbol':type()) -> clj_env:env().
analyze_symbol(Env, Symbol) ->
  case {namespace(Symbol), clj_env:get_local(Env, Symbol)} of
    {undefined, Local} when Local =/= undefined ->
      clj_env:push_expr(Env, Symbol);
    _ ->
      clj_env:push_expr(Env, Symbol)
  end.
