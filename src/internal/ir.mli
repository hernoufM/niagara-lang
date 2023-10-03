type literal =
  | LInteger of int
  | LRational of float
  | LMoney of int (* cents *)
  | LDate of Date.Date.t
  | LDuration of Date.Duration.t

(* Explicitly typed operators. It may be overkill, since the interpreter has no
   choice but to type check anyway. *)
type binop =
    IAdd
  | RAdd
  | MAdd
  | DAdd
  | DrAdd
  | ISub
  | RSub
  | MSub
  | DSub
  | DrSub
  | IMult
  | RMult
  | MMult
  | DrMult
  | IDiv
  | RDiv
  | MDiv
  | DrDiv

(* When refering to a variable, it can either mean to look at the total value
   or the value added at the current execution step *)
type flow_view = AtInstant | Cumulated

type formula =
  | Literal of literal
  | Variable of Variable.t * flow_view
  | Binop of binop * formula * formula
  | RCast of formula (* again related to types, might not be useful *)

type comp = Eq

(* For event expression, we consider when-expressions to be distinct from the
   original event, because the semantics of activation differs. *)
type event =
  | EvtVar of Variable.t
  | EvtOnRaise of Variable.t
  | EvtAnd of event * event
  | EvtOr of event * event
  | EvtComp of comp * formula * formula
  | EvtDate of formula

module RedistTree : sig

  (* Dummy types for GADT typing *)
  type flat = private FLAT
  type frac = private FRAC

  type 'a redist =
      NoInfo
    | Shares : float Variable.Map.t -> frac redist
    | Flats : { transfers : formula Variable.Map.t;
                balances : float Variable.Map.t }
        -> flat redist

  type 'a tree =
    | Nothing
    | Redist of 'a redist
    | When : (Variable.t * flat tree) list -> flat tree
    | Branch of { evt : Variable.t; before : 'a tree; after : 'a tree }

  (* Default and deficit are resolved by constructing a specific tree, which
     require an additional analysis *)
  type frac_balance =
    | BalanceVars of { default : Variable.t option; deficit : Variable.t option }
    | BalanceTree of frac tree

  (* An actual tree is distinguished between fractionnal redistribution (pools)
     and flat transfers (providing actors). While they are structurally similar,
     we forbid them to coexist on a same source because of the implied dodgy
     semantics (how to check for fraction completeness when there might be flat
     chunks of the pool dynamically redistributed).

     One tree is composed of several smaller trees, mirroring the source program
     structure, to avoid the explosion of event branching that can appears when
     merging them all together. Although, this is made meaningless when the
     default computation inevitably needs the fully composed tree. This needs
     consideration at some point .*)
  type t =
    | Flat of flat tree list
    | Fractions of {
        base_shares : frac redist;
        balance : frac_balance;
        branches : frac tree list;
      }

  (* Expliciting types to make construction tractable from the AST. *)

  type kind_tree =
    | NothingTree
    | FlatTree of flat tree
    | FracTree of frac tree

  type kind_redist =
      FlatRedist of flat redist
    | FracRedist of frac redist

  (* Construction functions. Will raise errors on mismatching GADT types *)

  val share : Variable.t -> formula * ValueType.t -> kind_redist
  val flat : Variable.t -> formula * ValueType.t -> kind_redist
  val tredist : kind_redist -> kind_tree
  val twhen : (Variable.t * kind_tree) list -> kind_tree
  val tbranch : Variable.t -> kind_tree -> kind_tree -> kind_tree
  val merge_redist : kind_redist -> kind_redist -> kind_redist
  val add_remainder : Variable.t -> t -> t
  val add_deficit : Variable.t -> t -> t
  val add_tree : kind_tree -> t -> t
  val of_tree : kind_tree -> t
  val of_remainder : Variable.t -> t
  val of_deficit : Variable.t -> t

end

(* Expression language for event equation.

   Distinction of [ESrc], which is [ECurrVar v] where [v] is, for the equation
   purpose, the variable that is currently flowing. This is done to have an
   equation tailored for each variable that can be a source during the
   execution. This obviously means that we duplicate a lot of informations,
   compared to a representation without [ESrc], but the gain is that we won't
   have to dynamically flip around this equation depending on the current source
   during execution. Here, the equations, once normalized, can just be computed
   as-is to obtain the threshold of the current source. The trade-off balance is
   still unclear as it will depend on the input program complexity, and the user
   experience and hotpaths. *)

type eqex =
  | EZero
  | ESrc
  | EConst of literal
  | EMult of float * eqex
  | EAdd of eqex * eqex
  | EMinus of eqex
  | EVar of Variable.t
  | ECurrVar of Variable.t

type cond =
  | CRef of Variable.t
  | CRaising of Variable.t
  | CEq of eqex * eqex
  | CNorm of float * eqex (* [source factor * "constant" expr]. Proper threshold
                             analysis should produce only normalized
                             equations. *)

type 'a sourced = {
  pinned_src : 'a Variable.Map.t;
  other_src : 'a;
}

type event_eq = cond Variable.BDT.t sourced

type program = {
  infos : Surface.Ast.program_infos;
  trees : RedistTree.t Variable.Map.t;
  events : event Variable.Map.t;
  eval_order : Variable.t list;
  equations : event_eq Variable.Map.t;
}

(* Fetch the payload associated to the given varaible, defaults to
   [other_src]. *)
val get_source : Variable.t -> 'a sourced -> 'a
