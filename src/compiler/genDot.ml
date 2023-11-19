open Odot
open Surface
open Internal
open Ir

let label s =
  Simple_id "label", Some (Double_quoted_id s)

let tlabel s =
  Simple_id "taillabel", Some (Double_quoted_id s)

let color s =
  Simple_id "color", Some (Double_quoted_id s)

let shape s =
  Simple_id "shape", Some (Double_quoted_id s)

let add_var p g v =
  let is_actor = Variable.Map.mem v p.infos.Ast.actors in
  let ncolor =
    if is_actor then color "red" else color "blue"
  in
  let n =
    Double_quoted_id(Format.asprintf "%a"
                       (FormatIr.print_variable ~with_ctx:(not is_actor) p.infos) v),
    None
  in
  g.stmt_list <- Stmt_node (n,[ncolor])::g.stmt_list;
  n

let id = let c = ref 0 in fun () -> incr c; "anon"^(string_of_int !c)

let add_event p g v =
  let n = Double_quoted_id(id ()), None in
  g.stmt_list <-
    Stmt_node (n,
               [shape "box";
                label (Format.asprintf "%a" (FormatIr.print_variable ~with_ctx:false p.infos) v)
               ])
    ::g.stmt_list;
  n

let add_edge g s e ls =
  if s <> e then
  g.stmt_list <-
    Stmt_edge (Edge_node_id s, [Edge_node_id e],ls)
    ::g.stmt_list

let dot_of_redist (type a) p g (r : a Ir.RedistTree.redist) =
  match r with
  | NoInfo -> []
  | Shares sh ->
    Variable.Map.fold (fun v f es ->
        let dest = add_var p g v in
        let attr = [ label (Format.asprintf "%a%%" R.pp_print R.(f * ~$100)) ] in
        (dest, attr)::es)
      sh []
  | Flats fs ->
    let es =
      Variable.Map.fold (fun dest s es ->
          let dest = add_var p g dest in
          let attr = [ label (Format.asprintf "%a" (FormatIr.print_formula p.infos) s) ] in
          (dest, attr)::es)
        fs.transfers []
    in
    Variable.Map.fold (fun dest f es ->
        let dest = add_var p g dest in
        let attr = [ label (Format.asprintf "deficit %a%%" R.pp_print R.(f * ~$100)) ] in
        (dest, attr)::es)
      fs.balances es

let rec dot_of_tree : type a. program -> graph -> a Ir.RedistTree.tree -> ((id * _ option) * attr list) list =
  fun p g t ->
  match t with
  | NoAction -> []
  | Action r ->
    dot_of_redist p g r
  | Decision (evt, after,before) ->
    let e = add_event p g evt in
    let bf = dot_of_tree p g before in
    let af = dot_of_tree p g after in
    List.iter (fun (bn,l) -> add_edge g e bn ((tlabel "avant")::l)) bf;
    List.iter (fun (an,l) -> add_edge g e an ((tlabel "apres")::l)) af;
    [e, []]

let dot_of_trees p g ts =
  List.map (dot_of_tree p g) ts
  |> List.flatten

let dot_of_t p g src t =
  match (t : Ir.RedistTree.t) with
  | Fractions { base_shares; balance; branches } ->
    dot_of_redist p g base_shares
    @ dot_of_trees p g branches
    @ (match (balance : Ir.RedistTree.frac_balance) with
    | BalanceVars b ->
      begin match b.deficit with
        | None -> ()
        | Some v ->
          let v = add_var p g v in
          add_edge g v src [label "deficit"]
      end;
      begin match b.default with
        | None -> []
        | Some v ->
          let v = add_var p g v in
          [v, [label "default"]]
      end
    | BalanceTree tree -> dot_of_tree p g tree)
  | Flat fs -> dot_of_trees p g fs

let graph_of_program p =
  let graph = {
    strict = false;
    kind = Digraph;
    id = None;
    stmt_list = [
      (* Stmt_attr (Attr_graph [Simple_id "ranksep", Some (Simple_id "0.8")]) *)
    ];
  }
  in
  Variable.Map.iter (fun v t ->
      let src = add_var p graph v in
      let es = dot_of_t p graph src t in
      List.iter (fun (e,a) ->
          add_edge graph src e a)
        es)
    p.trees;
  graph

let dot_srting_of_program p =
  string_of_graph @@ graph_of_program p

let dot_of_program p =
  print_file "graph.dot" @@ graph_of_program p
