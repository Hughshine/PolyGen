Require Import ZArith.
Require Import List.
Require Import Bool.
Require Import Psatz.
Require Import Setoid Morphisms.
Require Import Permutation.

Require Import Linalg.
Require Import Loop.
Require Import PolyLoop.
Require Import PolyLang.
Require Import Misc.
Require Import Semantics.
Require Import Instr.
Require Import VplInterface.
Require Import Result.
Require Import Canonizer.
Require Import Heuristics.
Require Import Projection.
Require Import TopoSort.
Require Import LoopGen.

Require Import Vpl.Impure.
Require Import ImpureAlarmConfig.

Open Scope Z_scope.
Open Scope list_scope.

Definition isBottom pol :=
  BIND p <- lift (ExactCs.fromCs_unchecked (poly_to_Cs pol)) -; lift (CstrDomain.isBottom p).

Lemma isBottom_correct :
  forall pol t, 0 < t -> If isBottom pol THEN forall p, in_poly p (expand_poly t pol) = false.
Proof.
  intros pol t Ht b Hbot.
  destruct b; simpl; [|auto]. intros p.
  unfold isBottom in Hbot.
  apply mayReturn_bind in Hbot; destruct Hbot as [p1 [Hp1 Hbot]].
  apply mayReturn_lift in Hp1; apply mayReturn_lift in Hbot.
  apply CstrDomain.isBottom_correct in Hbot; simpl in Hbot.
  apply ExactCs.fromCs_unchecked_correct in Hp1.
  apply not_true_is_false; intros Hin.
  rewrite <- poly_to_Cs_correct_Q in Hin by auto.
  eauto.
Qed.

Lemma isBottom_correct_1 :
  forall pol, If isBottom pol THEN forall p, in_poly p pol = false.
Proof.
  intros pol. generalize (isBottom_correct pol 1).
  rewrite expand_poly_1. intros H; apply H; lia.
Qed.

Definition isIncl pol1 pol2 :=
  BIND p1 <- lift (ExactCs.fromCs_unchecked (poly_to_Cs pol1)) -;
  BIND p2 <- lift (ExactCs.fromCs (poly_to_Cs pol2)) -;
  match p2 with Some p2 => lift (CstrDomain.isIncl p1 p2) | None => pure false end.

Lemma isIncl_correct :
  forall pol1 pol2 t, 0 < t -> If isIncl pol1 pol2 THEN forall p, in_poly p (expand_poly t pol1) = true -> in_poly p (expand_poly t pol2) = true.
Proof.
  intros pol1 pol2 t Ht b Hincl.
  destruct b; simpl; [|auto]. intros p Hin.
  unfold isIncl in Hincl.
  bind_imp_destruct Hincl p1 Hp1; bind_imp_destruct Hincl p2 Hp2.
  destruct p2 as [p2|]; [|apply mayReturn_pure in Hincl; congruence].
  apply mayReturn_lift in Hp1; apply mayReturn_lift in Hp2; apply mayReturn_lift in Hincl.
  apply CstrDomain.isIncl_correct in Hincl; simpl in Hincl.
  apply ExactCs.fromCs_unchecked_correct in Hp1.
  eapply ExactCs.fromCs_correct in Hp2.
  rewrite <- poly_to_Cs_correct_Q in Hin by auto.
  apply Hp1, Hincl in Hin. rewrite Hp2 in Hin.
  rewrite poly_to_Cs_correct_Q in Hin by auto.
  auto.
Qed.

Lemma isIncl_correct_1 :
  forall pol1 pol2, If isIncl pol1 pol2 THEN forall p, in_poly p pol1 = true -> in_poly p pol2 = true.
Proof.
  intros pol1 pol2. generalize (isIncl_correct pol1 pol2 1).
  rewrite !expand_poly_1. intros H; apply H; lia.
Qed.

Definition canPrecede n pol1 pol2 :=
  forall p1 x, in_poly p1 pol1 = true -> in_poly (assign n x p1) pol2 = true -> nth n p1 0 < x.

Definition check_canPrecede n (pol1 pol2 proj1 : polyhedron) :=
  let g1 := filter (fun c => 0 <? nth n (fst c) 0) pol1 in
  isBottom (pol2 ++ proj1 ++ g1).

Lemma check_canPrecede_correct :
  forall n pol1 pol2 proj1,
    isExactProjection n pol1 proj1 ->
    If check_canPrecede n pol1 pol2 proj1 THEN canPrecede n pol1 pol2.
Proof.
  intros n pol1 pol2 proj1 Hproj1 b Hprec.
  destruct b; simpl; [|auto].
  intros p1 x Hp1 Hpx.
  unfold check_canPrecede in Hprec. apply isBottom_correct_1 in Hprec; simpl in Hprec.
  specialize (Hprec (assign n x p1)). rewrite !in_poly_app in Hprec. reflect.
  rewrite Hpx in Hprec.
  apply isExactProjection_weaken1 in Hproj1. eapply isExactProjection_assign_1 in Hproj1; [|exact Hp1].
  rewrite Hproj1 in Hprec.
  destruct Hprec as [? | [? | Hprec]]; try congruence.
  assert (Hin : in_poly p1 (filter (fun c => 0 <? nth n (fst c) 0) pol1) = true).
  - unfold in_poly in *; rewrite forallb_forall in *.
    intros c. rewrite filter_In. intros; apply Hp1; tauto.
  - rewrite <- Z.nle_gt. intros Hle.
    eapply eq_true_false_abs; [|exact Hprec].
    unfold in_poly in *; rewrite forallb_forall in *.
    intros c. rewrite filter_In. intros Hc.
    specialize (Hin c). rewrite filter_In in Hin. specialize (Hin Hc).
    destruct Hc as [Hcin Hc].
    unfold satisfies_constraint in *. reflect. rewrite dot_product_assign_left.
    nia.
Qed.


Module Proj := FourierMotzkinProject CoreAlarmed.
Module Canon := VplCanonizer.
Module PPI := PolyProjectImpl CoreAlarmed Canon Proj.
Import PPI.

Global Opaque project.

(** * Generating the code *)

Fixpoint generate_loop (d : nat) (n : nat) (pi : Polyhedral_Instruction) : imp poly_stmt :=
  match d with
  | O => pure (PInstr pi.(pi_instr) (map (fun t => (1%positive, t)) pi.(pi_transformation)))
  | S d1 =>
    BIND proj <- project ((n - d1)%nat, pi.(pi_poly)) -;
    BIND inner <- generate_loop d1 n pi -;
    pure (PLoop (filter (fun c => negb (nth (n - d)%nat (fst c) 0 =? 0)) proj) inner)
  end.

Lemma env_scan_begin :
  forall polys env n p m, env_scan polys env n m p = true -> p =v= env ++ skipn (length env) p.
Proof.
  intros polys env n p m Hscan. unfold env_scan in Hscan. destruct (nth_error polys m); [|congruence].
  reflect. destruct Hscan as [[Heq1 Heq2] Heq3].
  apply same_length_eq in Heq1; [|rewrite resize_length; auto].
  rewrite Heq1 at 1.
  rewrite resize_skipn_eq; reflexivity.
Qed.
  
Lemma env_scan_single :
  forall polys env n p m, length env = n -> env_scan polys env n m p = true -> env =v= p.
Proof.
  intros polys env n p m Hlen Hscan.
  unfold env_scan in Hscan. destruct (nth_error polys m); [|congruence].
  reflect. destruct Hscan as [[Heq1 Heq2] Heq3]. rewrite Hlen in Heq1.
  rewrite Heq1. symmetry. auto.
Qed.

Lemma env_scan_split :
  forall polys env n p m, (length env < n)%nat -> env_scan polys env n m p = true <-> (exists x, env_scan polys (env ++ (x :: nil)) n m p = true).
Proof.
  intros polys env n p m Hlen.
  unfold env_scan. destruct (nth_error polys m); simpl; [|split; [intros; congruence|intros [x Hx]; auto]].
  split.
  - intros H. exists (nth (length env) p 0).
    reflect. destruct H as [[H1 H2] H3].
    split; [split|]; auto.
    rewrite app_length. simpl. rewrite <- resize_skipn_eq with (l := p) (d := length env) at 2.
    rewrite resize_app_le by (rewrite resize_length; lia).
    rewrite resize_length. rewrite <- is_eq_veq.
    rewrite is_eq_app by (rewrite resize_length; auto).
    reflect; split; auto.
    replace (length env + 1 - length env)%nat with 1%nat by lia.
    simpl. transitivity (nth 0 (skipn (length env) p) 0 :: nil).
    + rewrite nth_skipn. rewrite Nat.add_0_r. reflexivity.
    + destruct (skipn (length env) p); simpl; reflexivity.
  - intros [x Hx]. reflect. destruct Hx as [[H1 H2] H3].
    + split; [split|]; auto.
      rewrite app_length in H1. simpl in H1.
      rewrite <- is_eq_veq in H1. rewrite is_eq_app_left in H1.
      reflect; destruct H1 as [H1 H4]. rewrite resize_resize in H1 by lia. assumption.
Qed.

Lemma generate_loop_single_point :
  forall n pi env mem1 mem2,
    WHEN st <- generate_loop 0%nat n pi THEN
    poly_loop_semantics st env mem1 mem2 ->
    length env = n ->
    in_poly (rev env) pi.(pi_poly) = true ->
    env_poly_lex_semantics (rev env) n (pi :: nil) mem1 mem2.
Proof.
  intros n pi env mem1 mem2 st Hgen Hsem Hlen Henvsat. simpl in *.
  apply mayReturn_pure in Hgen.
  unfold env_poly_lex_semantics.
  eapply PolyLexProgress with (n := 0%nat) (p := rev env); [ |reflexivity| | | apply PolyLexDone].
  - unfold env_scan. simpl. reflect. split; [split|].
    + rewrite resize_eq; reflexivity.
    + rewrite resize_eq; [reflexivity | rewrite rev_length; lia].
    + auto.
  - intros n2 p2 Hcmp. apply not_true_iff_false; intros H.
    apply env_scan_single in H; [|rewrite rev_length; auto].
    rewrite H in Hcmp. rewrite lex_compare_reflexive in Hcmp. congruence.
  - rewrite <- Hgen in Hsem. inversion_clear Hsem.
    unfold affine_product in *. rewrite map_map in H.
    erewrite map_ext in H; [exact H|].
    intros; unfold eval_affine_expr; simpl. apply Z.div_1_r.
  - intros n1 p1. unfold scanned.
    destruct n1 as [|n1]; [|destruct n1; simpl; auto]. simpl.
    apply not_true_iff_false; intros H; reflect; destruct H as [H1 H2].
    apply env_scan_single in H1; [|rewrite rev_length; lia].
    rewrite H1 in H2; rewrite is_eq_reflexive in H2.
    destruct H2; congruence.
Qed.

Lemma env_scan_extend :
  forall d n pi lb ub env m p,
    length env = n ->
    (n < d)%nat ->
    WHEN proj <- project (S n, pi.(pi_poly)) THEN
    (forall x, (forall c, In c proj -> nth n (fst c) 0 <> 0 -> satisfies_constraint (rev (x :: env)) c = true) <-> lb <= x < ub) ->
    env_scan (pi :: nil) (rev env) d m p =
      existsb (fun x : Z => env_scan (pi :: nil) (rev env ++ x :: nil) d m p) (Zrange lb ub).
Proof.
  intros d n pi lb ub env m p Hlen Hnd proj Hproj Hlbub.
  rewrite eq_iff_eq_true. rewrite existsb_exists.
  rewrite env_scan_split by (rewrite rev_length; lia).
  split.
  - intros [x Hscan]; exists x; split; [|auto].
    rewrite Zrange_in. unfold env_scan in Hscan. destruct m; [|destruct m; simpl in Hscan; try congruence].
    simpl in Hscan. reflect.
    destruct Hscan as [[Hscan1 Hscan2] Hscan3].
    assert (Hinproj : in_poly (rev env ++ x :: nil) proj = true).
    {
      rewrite Hscan1. eapply project_inclusion; [apply Hscan3|].
      rewrite app_length; rewrite rev_length; rewrite Hlen; unfold length.
      replace (n + 1)%nat with (S n) by lia. apply Hproj.
    }
    rewrite <- Hlbub by eauto.
    unfold in_poly in Hinproj. rewrite forallb_forall in Hinproj.
    intros; auto.
  - intros [x [H1 H2]]; exists x; assumption.
Qed.

Lemma env_scan_inj_nth :
  forall pis env1 env2 n m p s, length env1 = length env2 -> (s < length env1)%nat ->
                           env_scan pis env1 n m p = true -> env_scan pis env2 n m p = true -> nth s env1 0 = nth s env2 0.
Proof.
  intros pis env1 env2 n m p s Hleneq Hs Henv1 Henv2.
  unfold env_scan in Henv1, Henv2. destruct (nth_error pis m) as [pi|]; [|congruence].
  reflect. rewrite Hleneq in Henv1. destruct Henv1 as [[Henv1 ?] ?]; destruct Henv2 as [[Henv2 ?] ?].
  rewrite <- Henv2 in Henv1. apply nth_eq; auto.
Qed.

Lemma env_scan_inj_rev :
  forall pis env n m x1 x2 p, env_scan pis (rev (x1 :: env)) n m p = true -> env_scan pis (rev (x2 :: env)) n m p = true -> x1 = x2.
Proof.
  intros pis env n m x1 x2 p H1 H2.
  replace x1 with (nth (length env) (rev (x1 :: env)) 0) by (simpl; rewrite app_nth2, rev_length, Nat.sub_diag; reflexivity || rewrite rev_length; lia).
  replace x2 with (nth (length env) (rev (x2 :: env)) 0) by (simpl; rewrite app_nth2, rev_length, Nat.sub_diag; reflexivity || rewrite rev_length; lia).
  eapply env_scan_inj_nth; [| |exact H1|exact H2]; rewrite !rev_length; simpl; lia.
Qed.

Theorem generate_loop_preserves_sem :
  forall d n pi env mem1 mem2,
    (d <= n)%nat ->
    WHEN st <- generate_loop d n pi THEN
    poly_loop_semantics st env mem1 mem2 ->
    length env = (n - d)%nat ->
    (forall c, In c pi.(pi_poly) -> fst c =v= resize n (fst c)) ->
    project_invariant (n - d)%nat pi.(pi_poly) (rev env) ->
    env_poly_lex_semantics (rev env) n (pi :: nil) mem1 mem2.
Proof.
  induction d.
  - intros n pi env mem1 mem2 Hnd st Hgen Hsem Hlen Hpilen Hinv.
    eapply generate_loop_single_point; eauto; try lia.
    eapply project_id; eauto.
    rewrite Nat.sub_0_r in Hinv. auto.
  - intros n pi env mem1 mem2 Hnd st Hgen Hsem Hlen Hpilen Hinv. simpl in *.
    bind_imp_destruct Hgen proj Hproj.
    bind_imp_destruct Hgen inner Hinner.
    apply mayReturn_pure in Hgen. rewrite <- Hgen in Hsem.
    apply PLLoop_inv_sem in Hsem.
    destruct Hsem as [lb [ub [Hlbub Hsem]]].
    unfold env_poly_lex_semantics in *.
    eapply poly_lex_semantics_extensionality.
    + apply poly_lex_concat_seq with (to_scans := fun x => env_scan (pi :: nil) (rev (x :: env)) n).
      * eapply iter_semantics_map; [|apply Hsem].
        intros x mem3 mem4 Hbounds Hloop. eapply IHd with (env := x :: env); simpl; eauto; try lia.
        replace (n - d)%nat with (S (n - S d))%nat in * by lia.
        eapply project_next_r_inclusion; [|exact Hproj|].
        -- rewrite project_invariant_resize, resize_app by (rewrite rev_length; auto).
           apply Hinv.
        -- intros c Hcin Hcnth. rewrite Zrange_in, <- Hlbub in Hbounds.
           unfold in_poly in Hbounds; rewrite forallb_forall in Hbounds. apply Hbounds.
           rewrite filter_In; reflect; auto.
      * intros x. apply env_scan_proper.
      * intros x1 k1 x2 k2 m p H1 H2 H3 H4. rewrite Zrange_nth_error in *.
        enough (lb + Z.of_nat k1 = lb + Z.of_nat k2) by lia.
        eapply env_scan_inj_rev; [destruct H3 as [? <-]; exact H1|destruct H4 as [? <-]; exact H2].
      * intros x1 n1 p1 k1 x2 n2 p2 k2 Hcmp H1 H2 H3 H4.
        rewrite Zrange_nth_error in *.
        apply env_scan_begin in H1; apply env_scan_begin in H2. simpl in *.
        rewrite H1, H2 in Hcmp.
        enough (lb + Z.of_nat k2 <= lb + Z.of_nat k1) by lia.
        eapply lex_app_not_gt.
        destruct H3 as [? <-]; destruct H4 as [? <-].
        rewrite Hcmp; congruence.
    + simpl. intros m p. rewrite env_scan_extend; eauto; try lia.
      * replace (S (n - S d)) with (n - d)%nat by lia. apply Hproj.
      * intros x; rewrite <- Hlbub. unfold in_poly; rewrite forallb_forall. apply forall_ext; intros c.
        split; intros H; intros; apply H; rewrite filter_In in *; reflect; tauto.
Qed.

Definition generate d n pi :=
  BIND st <- generate_loop d n pi -;
  BIND ctx <- project_invariant_export ((n - d)%nat, pi.(pi_poly)) -;
  pure (PGuard ctx st).

Theorem generate_preserves_sem :
  forall d n pi env mem1 mem2,
    (d <= n)%nat ->
    WHEN st <- generate d n pi THEN
    poly_loop_semantics st env mem1 mem2 ->
    length env = (n - d)%nat ->
    (forall c, In c pi.(pi_poly) -> fst c =v= resize n (fst c)) ->
    env_poly_lex_semantics (rev env) n (pi :: nil) mem1 mem2.
Proof.
  intros d n pi env mem1 mem2 Hd st Hgen Hloop Henv Hsize.
  bind_imp_destruct Hgen st1 H. bind_imp_destruct Hgen ctx Hctx.
  apply mayReturn_pure in Hgen.
  rewrite <- Hgen in *.
  apply PLGuard_inv_sem in Hloop.
  destruct (in_poly (rev env) ctx) eqn:Htest.
  - eapply generate_loop_preserves_sem; eauto.
    rewrite <- (project_invariant_export_correct _ _ _ _ Hctx); eauto.
  - rewrite Hloop. apply PolyLexDone. intros n0 p. unfold env_scan.
    destruct n0; simpl in *; [|destruct n0]; auto. reflect.
    rewrite rev_length; rewrite Henv.
    destruct (is_eq (rev env) (resize (n - d)%nat p)) eqn:Hpenv; auto.
    destruct (in_poly p pi.(pi_poly)) eqn:Hpin; auto. exfalso.
    eapply project_invariant_inclusion in Hpin.
    rewrite <- (project_invariant_export_correct _ _ _ _ Hctx) in Hpin.
    reflect. rewrite <- Hpenv in Hpin. congruence.
Qed.



Definition complete_generate d n pi :=
  BIND polyloop <- generate d n pi -;
  polyloop_to_loop (n - d)%nat polyloop.

Theorem complete_generate_preserve_sem :
  forall d n pi env mem1 mem2,
    (d <= n)%nat ->
    WHEN st <- complete_generate d n pi THEN
    loop_semantics st env mem1 mem2 ->
    length env = (n - d)%nat ->
    (forall c, In c pi.(pi_poly) -> fst c =v= resize n (fst c)) ->
    env_poly_lex_semantics (rev env) n (pi :: nil) mem1 mem2.
Proof.
  intros d n pi env mem1 mem2 Hdn st Hst Hloop Henv Hsize.
  unfold complete_generate in Hst.
  bind_imp_destruct Hst polyloop Hpolyloop.
  eapply generate_preserves_sem; eauto.
  eapply polyloop_to_loop_correct; eauto.
Qed.

Fixpoint make_seq l :=
  match l with
  | nil => PSkip
  | x :: l => PSeq x (make_seq l)
  end.

Lemma make_seq_semantics :
  forall l env mem1 mem2, poly_loop_semantics (make_seq l) env mem1 mem2 <->
                     iter_semantics (fun s => poly_loop_semantics s env) l mem1 mem2.
Proof.
  induction l.
  - intros; split; intros H; inversion_clear H; constructor.
  - intros; split; simpl; intros H; inversion_clear H; econstructor; eauto; rewrite IHl in *; eauto.
Qed.


Definition update_poly pi pol :=
  {| pi_instr := pi.(pi_instr) ; pi_poly := pol ; pi_schedule := pi.(pi_schedule) ; pi_transformation := pi.(pi_transformation) |}.

Definition poly_inter_pure (p1 p2 : polyhedron) : polyhedron := p1 ++ p2.
Lemma poly_inter_pure_def :
  forall p pol1 pol2, in_poly p (poly_inter_pure pol1 pol2) = in_poly p pol1 && in_poly p pol2.
Proof.
  intros p pol1 pol2; unfold poly_inter_pure, in_poly.
  rewrite forallb_app; reflexivity.
Qed.

Definition poly_inter p1 p2 :=
  Canon.canonize (poly_inter_pure p1 p2).
Lemma poly_inter_def :
  forall p pol1 pol2, WHEN pol <- poly_inter pol1 pol2 THEN in_poly p pol = in_poly p (poly_inter_pure pol1 pol2).
Proof.
  intros p pol1 pol2 pol Hinter.
  apply Canon.canonize_correct in Hinter.
  specialize (Hinter 1 p). rewrite !expand_poly_1 in Hinter.
  apply Hinter; lia.
Qed.

Lemma poly_inter_pure_no_new_var :
  forall pol1 pol2 k, absent_var pol1 k -> absent_var pol2 k -> absent_var (poly_inter_pure pol1 pol2) k.
Proof.
  intros pol1 pol2 k H1 H2 c Hc.
  rewrite in_app_iff in Hc; destruct Hc; auto.
Qed.

Lemma poly_inter_no_new_var :
  forall pol1 pol2 k, absent_var pol1 k -> absent_var pol2 k ->
                 WHEN pol <- poly_inter pol1 pol2 THEN absent_var pol k.
Proof.
  intros pol1 pol2 k H1 H2 pol Hpol.
  apply Canon.canonize_no_new_var with (k := k) in Hpol; [auto|].
  apply poly_inter_pure_no_new_var; auto.
Qed.

Lemma poly_inter_nrl :
  forall pol1 pol2 n, (poly_nrl pol1 <= n)%nat -> (poly_nrl pol2 <= n)%nat ->
                 WHEN pol <- poly_inter pol1 pol2 THEN (poly_nrl pol <= n)%nat.
Proof.
  intros pol1 pol2 n H1 H2 pol Hpol.
  rewrite has_var_poly_nrl in *.
  intros k Hnk; eapply poly_inter_no_new_var; [| |exact Hpol]; eauto.
Qed.

Definition dummy_pi := {|
  pi_instr := dummy_instr ;
  pi_poly := nil ;
  pi_transformation := nil ;
  pi_schedule := nil
|}.

Fixpoint poly_difference p1 p2 :=
  match p2 with
  | nil => pure nil
  | c :: p2 =>
    BIND pl1 <- VplCanonizerZ.canonize (neg_constraint c :: p1) -;
    BIND diff <- poly_difference (c :: p1) p2 -;
    BIND b <- isBottom pl1 -;
    pure (if b then diff else (pl1 :: diff))
  end.

Lemma poly_difference_def :
  forall p2 p1 v, WHEN pl <- poly_difference p1 p2 THEN
                  existsb (in_poly v) pl = in_poly v p1 && negb (in_poly v p2).
Proof.
  induction p2.
  - intros p1 v pl Hpl. apply mayReturn_pure in Hpl; rewrite <- Hpl. simpl. destruct in_poly; auto.
  - intros p1 v pl Hpl. simpl in *.
    bind_imp_destruct Hpl pl1 Hpl1; bind_imp_destruct Hpl diff Hdiff; bind_imp_destruct Hpl empty Hempty; apply mayReturn_pure in Hpl; rewrite <- Hpl.
    transitivity (existsb (in_poly v) (pl1 :: diff)).
    { destruct empty; simpl; [|reflexivity]. eapply isBottom_correct_1 in Hempty; simpl in *; rewrite Hempty; reflexivity. }
    simpl. rewrite IHp2; [|eauto].
    rewrite VplCanonizerZ.canonize_correct; [|eauto]. simpl.
    rewrite neg_constraint_correct; unfold in_poly; simpl.
    destruct (satisfies_constraint v a); simpl.
    + reflexivity.
    + destruct forallb; reflexivity.
Qed.

Lemma poly_difference_no_new_var :
  forall p2 p1 k, absent_var p1 k -> absent_var p2 k ->
             WHEN pl <- poly_difference p1 p2 THEN forall p, In p pl -> absent_var p k.
Proof.
  induction p2.
  - intros p1 k Hp1 Hp2 pl Hpl p Hp. apply mayReturn_pure in Hpl; rewrite <- Hpl in *. simpl in *. tauto.
  - intros p1 k Hp1 Hp2 pl Hpl p Hp. simpl in *.
    bind_imp_destruct Hpl pl1 Hpl1; bind_imp_destruct Hpl diff Hdiff; bind_imp_destruct Hpl empty Hempty;
      apply mayReturn_pure in Hpl; rewrite <- Hpl in *.
    assert (Hin : In p (pl1 :: diff)) by (destruct empty; simpl in *; tauto).
    simpl in *. destruct Hin; [|eapply (IHp2 (a :: p1) k); eauto using absent_var_cons, absent_var_head, absent_var_tail].
    rewrite H in *.
    unfold absent_var. eapply VplCanonizerZ.canonize_no_new_var; [|eauto].
    apply absent_var_cons; [|auto].
    apply absent_var_head in Hp2; unfold neg_constraint; simpl; rewrite mult_nth.
    lia.
Qed.

Lemma poly_difference_nrl :
  forall p1 p2 n, (poly_nrl p1 <= n)%nat -> (poly_nrl p2 <= n)%nat ->
             WHEN pl <- poly_difference p1 p2 THEN (forall p, In p pl -> (poly_nrl p <= n)%nat).
Proof.
  intros p1 p2 n Hp1 Hp2 pl Hpl p Hp.
  rewrite has_var_poly_nrl in *.
  intros k Hk; eapply poly_difference_no_new_var; [| |exact Hpl|]; eauto.
Qed.

Lemma poly_difference_disjoint :
  forall p2 p1, WHEN pols <- poly_difference p1 p2 THEN all_disjoint pols.
Proof.
  induction p2.
  - intros p1 pols Hpols; simpl in *. apply mayReturn_pure in Hpols; rewrite <- Hpols.
    apply all_disjoint_nil.
  - intros p1 pols Hpols. simpl in *.
    bind_imp_destruct Hpols pl1 Hpl1; bind_imp_destruct Hpols diff Hdiff; bind_imp_destruct Hpols empty Hempty; apply mayReturn_pure in Hpols; rewrite <- Hpols.
    enough (all_disjoint (pl1 :: diff)) by (destruct empty; [eapply all_disjoint_cons_rev; eauto|auto]).
    apply all_disjoint_cons; [eapply IHp2; eauto|].
    intros p pol1 Hpolin Hinpl Hinpol1.
    rewrite VplCanonizerZ.canonize_correct in Hinpl; [|eauto].
    eapply poly_difference_def with (v := p) in Hdiff.
    unfold in_poly in *; simpl in *.
    rewrite neg_constraint_correct in Hinpl.
    destruct (satisfies_constraint p a) eqn:Hsat; simpl in *.
    + congruence.
    + rewrite existsb_forall in Hdiff; rewrite Hdiff in Hinpol1; [congruence|auto].
Qed.

Definition separate_polys pol1 pol2 :=
  BIND inter <- poly_inter pol1 pol2 -;
  BIND empty <- isBottom inter -;
  if empty then pure (nil, pol2 :: nil) else
  BIND diff <- poly_difference pol2 pol1 -;
  pure (inter :: nil, diff).

Lemma separate_polys_nrl :
  forall pol1 pol2 n, (poly_nrl pol1 <= n)%nat -> (poly_nrl pol2 <= n)%nat ->
                 WHEN sep <- separate_polys pol1 pol2 THEN
                      forall pol, In pol (fst sep ++ snd sep) -> (poly_nrl pol <= n)%nat.
Proof.
  intros pol1 pol2 n H1 H2 sep Hsep pol Hpol.
  unfold separate_polys in Hsep.
  bind_imp_destruct Hsep inter Hinter; bind_imp_destruct Hsep empty Hempty. destruct empty.
  - apply mayReturn_pure in Hsep; rewrite <- Hsep in *; simpl in *.
    destruct Hpol as [<- | ?]; tauto.
  - bind_imp_destruct Hsep diff Hdiff; apply mayReturn_pure in Hsep; rewrite <- Hsep in *.
    simpl in *.
    destruct Hpol as [<- | Hpol]; [|eapply poly_difference_nrl; [| |exact Hdiff|]; eauto].
    eapply poly_inter_nrl in Hinter; eauto.
Qed.

Lemma separate_polys_cover :
  forall pol1 pol2, WHEN sep <- separate_polys pol1 pol2 THEN
                    forall p, in_poly p pol2 = true <-> exists pol, In pol (fst sep ++ snd sep) /\ in_poly p pol = true.
Proof.
  intros pol1 pol2 sep Hsep p.
  unfold separate_polys in Hsep.
  bind_imp_destruct Hsep inter Hinter; bind_imp_destruct Hsep empty Hempty. destruct empty.
  - apply mayReturn_pure in Hsep; rewrite <- Hsep in *; simpl in *.
    split; [intros H; exists pol2; auto|intros [pol [H1 H2]]; intuition congruence].
  - bind_imp_destruct Hsep diff Hdiff; apply mayReturn_pure in Hsep; rewrite <- Hsep in *.
    simpl in *.
    apply poly_difference_def with (v := p) in Hdiff.
    apply poly_inter_def with (p := p) in Hinter; rewrite poly_inter_pure_def in Hinter.
    destruct (in_poly p pol1); simpl in *; split.
    + intros H; exists inter; intuition congruence.
    + intros [pol [[H1 | H1] H2]]; [congruence|]. rewrite andb_false_r, existsb_forall in Hdiff.
      specialize (Hdiff pol H1); congruence.
    + intros H; rewrite H, existsb_exists in Hdiff. destruct Hdiff as [pol [H1 H2]]; eauto.
    + intros [pol [[H1 | H1] H2]]; [congruence|]. rewrite andb_true_r in Hdiff; rewrite <- Hdiff, existsb_exists.
      eauto. 
Qed.

Lemma separate_polys_separate :
  forall pol1 pol2, WHEN sep <- separate_polys pol1 pol2 THEN
                    forall p pol, In pol (snd sep) -> in_poly p pol = true -> in_poly p pol1 = false.
Proof.
  intros pol1 pol2 sep Hsep p pol Hpolin Hinpol.
  unfold separate_polys in Hsep.
  bind_imp_destruct Hsep inter Hinter; bind_imp_destruct Hsep empty Hempty. destruct empty.
  - apply mayReturn_pure in Hsep; rewrite <- Hsep in *; simpl in *.
    destruct Hpolin as [<- | ?]; [|tauto].
    apply isBottom_correct_1 in Hempty; simpl in *. specialize (Hempty p).
    rewrite poly_inter_def in Hempty; [|eauto]. rewrite poly_inter_pure_def in Hempty.
    destruct (in_poly p pol1); simpl in *; congruence.
  - bind_imp_destruct Hsep diff Hdiff; apply mayReturn_pure in Hsep; rewrite <- Hsep in *.
    simpl in *.
    apply poly_difference_def with (v := p) in Hdiff.
    apply not_true_is_false; intros H. rewrite H, andb_false_r, existsb_forall in Hdiff.
    specialize (Hdiff pol Hpolin); congruence.
Qed.

Lemma separate_polys_disjoint :
  forall pol1 pol2, WHEN sep <- separate_polys pol1 pol2 THEN all_disjoint (fst sep ++ snd sep).
Proof.
  intros pol1 pol2 sep Hsep.
  unfold separate_polys in Hsep.
  bind_imp_destruct Hsep inter Hinter; bind_imp_destruct Hsep empty Hempty. destruct empty.
  - apply mayReturn_pure in Hsep; rewrite <- Hsep in *; simpl in *.
    apply all_disjoint_cons; [apply all_disjoint_nil|]. intros; simpl in *; auto.
  - bind_imp_destruct Hsep diff Hdiff; apply mayReturn_pure in Hsep; rewrite <- Hsep in *.
    apply all_disjoint_app.
    + simpl. apply all_disjoint_cons; [apply all_disjoint_nil|].
      intros; simpl in *; auto.
    + simpl. eapply poly_difference_disjoint; eauto.
    + intros p p1 p2 H1 H2 Hp1 Hp2; simpl in *. destruct H1 as [H1 | H1]; [|auto].
      apply poly_difference_def with (v := p) in Hdiff.
      apply poly_inter_def with (p := p) in Hinter; rewrite poly_inter_pure_def, H1 in Hinter.
      rewrite Hinter in Hp1; reflect. destruct Hp1 as [Hpol1 Hpol2]; rewrite Hpol1, andb_false_r in Hdiff.
      rewrite existsb_forall in Hdiff; specialize (Hdiff p2 H2). congruence.
Qed.  

Fixpoint split_polys_rec (l : list polyhedron) (n : nat) : imp (list (polyhedron * list nat)) :=
  match l with
  | nil => pure ((nil, nil) :: nil)
  | p :: l =>
    BIND spl <- split_polys_rec l (S n) -;
    BIND spl1 <- mapM (fun '(pol, pl) =>
         BIND sep <- separate_polys p pol -;
         pure (map (fun pp => (pp, n :: pl)) (fst sep) ++ map (fun pp => (pp, pl)) (snd sep))
    ) spl -;
    pure (flatten spl1)
  end.

Lemma split_polys_rec_index_correct :
  forall pols n, WHEN out <- split_polys_rec pols n THEN forall polpl i, In polpl out -> In i (snd polpl) -> (n <= i < n + length pols)%nat.
Proof.
  induction pols.
  - intros n out Hout ppl i Hin Hiin.
    simpl in *. apply mayReturn_pure in Hout. rewrite <- Hout in Hin.
    simpl in Hin; destruct Hin as [Hin | Hin]; [|tauto]. rewrite <- Hin in Hiin; simpl in Hiin; tauto.
  - intros n out Hout ppl i Hin Hiin.
    simpl in *.
    bind_imp_destruct Hout spl Hspl; bind_imp_destruct Hout spl1 Hspl1; apply mayReturn_pure in Hout; rewrite <- Hout in *.
    rewrite flatten_In in Hin. destruct Hin as [u [Hppl Hu]].
    eapply mapM_in_iff in Hu; [|eauto].
    destruct Hu as [[pol pl] [Hu Hpolpl]].
    bind_imp_destruct Hu sep Hsep. apply mayReturn_pure in Hu; rewrite <- Hu in *.
    simpl in Hppl. rewrite in_app_iff, !in_map_iff in Hppl.
    specialize (IHpols _ _ Hspl (pol, pl)); simpl in IHpols.
    destruct Hppl as [[? [Heq _]] | [? [Heq _]]]; rewrite <- Heq in Hiin; simpl in Hiin; [destruct Hiin as [Hiin | Hiin]; [lia|]|];
      specialize (IHpols i Hpolpl Hiin); lia.
Qed.

Lemma split_polys_rec_index_NoDup :
  forall pols n, WHEN out <- split_polys_rec pols n THEN forall polpl, In polpl out -> NoDup (snd polpl).
Proof.
  induction pols.
  - intros n out Hout ppl Hin.
    simpl in *. apply mayReturn_pure in Hout. rewrite <- Hout in Hin.
    simpl in Hin; destruct Hin as [Hin | Hin]; [|tauto]. rewrite <- Hin; constructor.
  - intros n out Hout ppl Hin.
    simpl in *.
    bind_imp_destruct Hout spl Hspl; bind_imp_destruct Hout spl1 Hspl1; apply mayReturn_pure in Hout; rewrite <- Hout in *.
    rewrite flatten_In in Hin. destruct Hin as [u [Hppl Hu]].
    eapply mapM_in_iff in Hu; [|eauto].
    destruct Hu as [[pol pl] [Hu Hpolpl]].
    bind_imp_destruct Hu sep Hsep. apply mayReturn_pure in Hu; rewrite <- Hu in *.
    simpl in Hppl. rewrite in_app_iff, !in_map_iff in Hppl.
    specialize (IHpols _ _ Hspl (pol, pl)); simpl in IHpols.
    destruct Hppl as [[? [Heq _]] | [? [Heq _]]]; rewrite <- Heq; simpl; [|intuition].
    constructor; [|intuition].
    intros H; eapply (split_polys_rec_index_correct _ _ _ Hspl _ _ Hpolpl) in H.
    lia.
Qed.

Lemma split_polys_rec_nrl :
  forall pols n, WHEN out <- split_polys_rec pols n THEN
                 forall k, (forall pol, In pol pols -> (poly_nrl pol <= k)%nat) -> (forall ppl, In ppl out -> (poly_nrl (fst ppl) <= k)%nat).
Proof.
  induction pols.
  - intros n out Hout k Hpols ppl Hin.
    simpl in *. apply mayReturn_pure in Hout. rewrite <- Hout in Hin.
    simpl in Hin; destruct Hin as [Hin | Hin]; [|tauto]. rewrite <- Hin; unfold poly_nrl; simpl; lia.
  - intros n out Hout k Hpols ppl Hin.
    simpl in *.
    bind_imp_destruct Hout spl Hspl; bind_imp_destruct Hout spl1 Hspl1; apply mayReturn_pure in Hout; rewrite <- Hout in *.
    rewrite flatten_In in Hin. destruct Hin as [u [Hppl Hu]].
    eapply mapM_in_iff in Hu; [|eauto].
    destruct Hu as [[pol pl] [Hu Hpolpl]].
    bind_imp_destruct Hu sep Hsep. apply mayReturn_pure in Hu; rewrite <- Hu in *.
    eapply separate_polys_nrl in Hsep; [apply Hsep|apply Hpols; auto|eapply (IHpols _ _ Hspl _ _ (pol, pl)); eauto]. Unshelve. 2:eauto.
    apply in_map with (f := fst) in Hppl; simpl in Hppl; rewrite map_app, !map_map, !map_id in Hppl.
    exact Hppl.
Qed.

Lemma split_polys_rec_disjoint :
  forall pols n, WHEN out <- split_polys_rec pols n THEN all_disjoint (map fst out).
Proof.
    induction pols.
  - intros n out Hout p k1 k2 ppl1 ppl2 Hk1 Hk2 Hppl1 Hppl2.
    simpl in *. apply mayReturn_pure in Hout. rewrite <- Hout in *.
    destruct k1 as [|[|k1]]; destruct k2 as [|[|k2]]; simpl in *; congruence.
  - intros n out Hout.
    simpl in *.
    bind_imp_destruct Hout spl Hspl; bind_imp_destruct Hout spl1 Hspl1; apply mayReturn_pure in Hout; rewrite <- Hout in *.
    rewrite flatten_map. apply all_disjoint_flatten.
    + intros l1 Hl1.
      rewrite in_map_iff in Hl1. destruct Hl1 as [pll [Hpll Hin1]]; rewrite <- Hpll.
      eapply mapM_in_iff in Hin1; [|eauto]. destruct Hin1 as [[pol pl] [H1 H2]].
      bind_imp_destruct H1 sep Hsep; apply mayReturn_pure in H1; rewrite <- H1.
      simpl; rewrite map_app, !map_map, !map_id.
      eapply separate_polys_disjoint; eauto.
    + intros p k1 k2 l1 l2 pol1 pol2 Hk1 Hk2 Hl1 Hl2 Hin1 Hin2.
      rewrite nth_error_map_iff in Hk1, Hk2.
      destruct Hk1 as [pll1 [Hk1 Hll1]]; destruct Hk2 as [pll2 [Hk2 Hll2]]; rewrite Hll1, Hll2 in *.
      eapply mapM_nth_error1 in Hk1; [|exact Hspl1]. destruct Hk1 as [[pp1 pl1] [H1 Hk1]].
      eapply mapM_nth_error1 in Hk2; [|exact Hspl1]. destruct Hk2 as [[pp2 pl2] [H2 Hk2]].
      bind_imp_destruct H1 sep1 Hsep1; bind_imp_destruct H2 sep2 Hsep2.
      apply mayReturn_pure in H1; apply mayReturn_pure in H2. rewrite <- H1 in Hl1; rewrite <- H2 in Hl2.
      simpl in Hl1, Hl2; rewrite map_app, !map_map, !map_id in Hl1, Hl2.
      assert (Ht1 : in_poly p pp1 = true) by (erewrite (separate_polys_cover _ _ _ Hsep1 _); exists pol1; auto).
      assert (Ht2 : in_poly p pp2 = true) by (erewrite (separate_polys_cover _ _ _ Hsep2 _); exists pol2; auto).
      apply map_nth_error with (f := fst) in Hk1; apply map_nth_error with (f := fst) in Hk2.
      specialize (IHpols _ _ Hspl _ _ _ _ _ Hk1 Hk2 Ht1 Ht2). auto.
Qed.

Lemma split_polys_rec_cover_all :
  forall pols n, WHEN out <- split_polys_rec pols n THEN forall p, exists ppl, In ppl out /\ in_poly p (fst ppl) = true /\
                                                               (forall k pol, nth_error pols k = Some pol -> in_poly p pol = true -> In (n + k)%nat (snd ppl)).
Proof.
  induction pols.
  - intros n out Hout p.
    simpl in *. apply mayReturn_pure in Hout. exists (nil, nil). rewrite <- Hout.
    simpl; split; [|split]; auto. intros [|k]; simpl; congruence.
  - intros n out Hout p.
    simpl in *.
    bind_imp_destruct Hout spl Hspl; bind_imp_destruct Hout spl1 Hspl1; apply mayReturn_pure in Hout; rewrite <- Hout in *.
    destruct (IHpols _ _ Hspl p) as [[pol pl] [Hppl1 [Hin1 Hins1]]]; simpl in *.
    apply In_nth_error in Hppl1. destruct Hppl1 as [k1 Hk1].
    destruct (mapM_nth_error2 _ _ _ _ _ _ Hk1 _ Hspl1) as [lppl [Hlppl Hk2]].
    apply nth_error_In in Hk2.
    bind_imp_destruct Hlppl sep Hsep; apply mayReturn_pure in Hlppl.
    eapply separate_polys_cover in Hin1; [|eauto]. destruct Hin1 as [pol1 [Hpol1in Hinpol1]].
    rewrite in_app_iff in Hpol1in.
    destruct Hpol1in as [Hpol1in | Hpol1in]; [exists (pol1, n :: pl)|exists (pol1, pl)]; simpl; rewrite flatten_In.
    all: split; [exists lppl; split; [rewrite <- Hlppl; simpl|auto]|split; [auto|]].
    + rewrite in_app_iff; left. rewrite in_map_iff; exists pol1. auto.
    + intros [|k] pol2 Hk Hin2; simpl in *; [left; lia|right; rewrite Nat.add_succ_r; eapply Hins1; eauto].
    + rewrite in_app_iff; right. rewrite in_map_iff; exists pol1. auto.
    + intros [|k] pol2 Hk Hin2; simpl in *; [|rewrite Nat.add_succ_r; eapply Hins1; eauto].
      exfalso. eapply separate_polys_separate in Hinpol1; eauto. congruence.
Qed.

Definition split_polys pols :=
  BIND spl <- split_polys_rec pols 0%nat -;
  pure (filter (fun ppl => match snd ppl with nil => false | _ => true end) spl).

Lemma split_polys_index_correct :
  forall pols, WHEN out <- split_polys pols THEN forall polpl i, In polpl out -> In i (snd polpl) -> (i < length pols)%nat.
Proof.
  intros pols out Hout ppl i H1 H2.
  bind_imp_destruct Hout out1 Hout1. apply mayReturn_pure in Hout; rewrite <- Hout in *.
  rewrite filter_In in H1.
  generalize (split_polys_rec_index_correct pols 0%nat out1 Hout1 ppl i). intuition lia.
Qed.

Lemma split_polys_index_NoDup :
  forall pols, WHEN out <- split_polys pols THEN forall polpl, In polpl out -> NoDup (snd polpl).
Proof.
  intros pols out Hout ppl Hin.
  bind_imp_destruct Hout out1 Hout1. apply mayReturn_pure in Hout; rewrite <- Hout in *.
  rewrite filter_In in Hin; destruct Hin.
  eapply (split_polys_rec_index_NoDup pols 0%nat); eauto.
Qed.

Lemma split_polys_nrl :
  forall pols, WHEN out <- split_polys pols THEN forall k, (forall pol, In pol pols -> (poly_nrl pol <= k)%nat) -> (forall ppl, In ppl out -> (poly_nrl (fst ppl) <= k)%nat).
Proof.
  intros pols out Hout k H ppl Hin.
  bind_imp_destruct Hout out1 Hout1. apply mayReturn_pure in Hout; rewrite <- Hout in *.
  rewrite filter_In in Hin; destruct Hin.
  eapply (split_polys_rec_nrl pols 0%nat); eauto.
Qed.

Lemma split_polys_disjoint :
  forall pols, WHEN out <- split_polys pols THEN all_disjoint (map fst out).
Proof.
  intros pols out Hout.
  bind_imp_destruct Hout out1 Hout1. apply mayReturn_pure in Hout; rewrite <- Hout in *.
  apply split_polys_rec_disjoint in Hout1.
  apply all_disjoint_map_filter. auto.
Qed.

Lemma split_polys_cover :
  forall pols, WHEN out <- split_polys pols THEN
          forall p pol i, nth_error pols i = Some pol -> in_poly p pol = true -> exists ppl, In ppl out /\ In i (snd ppl) /\ in_poly p (fst ppl) = true.
Proof.
  intros pols out Hout p pol i Hi Hin.
  bind_imp_destruct Hout out1 Hout1. apply mayReturn_pure in Hout; rewrite <- Hout in *.
  destruct (split_polys_rec_cover_all _ _ _ Hout1 p) as [ppl Hppl].
  exists ppl. destruct Hppl as [H1 [H2 H3]]; specialize (H3 i pol).
  rewrite filter_In. split; [|auto]. split; [auto|]. destruct (snd ppl); [|auto].
  exfalso; apply H3; auto.
Qed.

Definition build_dependency_matrix n pols :=
  mapM (fun pol1 =>
          BIND proj1 <- Proj.project (n, pol1) -;
          mapM (fun pol2 => fmap negb (check_canPrecede n pol1 pol2 proj1)) pols) pols.

Lemma build_dependency_matrix_length :
  forall n pols, WHEN out <- build_dependency_matrix n pols THEN length out = length pols.
Proof.
  intros n pols out Hout.
  unfold build_dependency_matrix in Hout.
  symmetry; eapply mapM_length; eauto.
Qed.

Lemma build_dependency_matrix_canPrecede :
  forall n pols, WHEN out <- build_dependency_matrix n pols THEN
                 forall k1 k2 ppl1 ppl2, nth_error pols k1 = Some ppl1 -> nth_error pols k2 = Some ppl2 ->
                                    nth k2 (nth k1 out nil) true = false ->
                                    canPrecede n ppl1 ppl2.
Proof.
  intros n pols out Hout k1 k2 ppl1 ppl2 Hk1 Hk2 H.
  unfold build_dependency_matrix in Hout.
  eapply mapM_nth_error2 with (k := k1) in Hout; [|eauto].
  destruct Hout as [row [Hrow Hout]].
  bind_imp_destruct Hrow proj Hproj.
  eapply mapM_nth_error2 with (k := k2) in Hrow; [|eauto].
  destruct Hrow as [b [Hb Hrow]].
  erewrite nth_error_nth with (n := k1) in H; [|eauto].
  erewrite nth_error_nth in H; [|eauto]. rewrite H in Hb.
  unfold fmap in Hb. bind_imp_destruct Hb b1 Hb1; apply mayReturn_pure in Hb.
  destruct b1; simpl in *; [|congruence].
  eapply check_canPrecede_correct in Hb1; simpl in Hb1; [auto|].
  eapply Proj.project_in_iff; eauto.
Qed.

Definition split_and_sort n pols :=
  BIND spl <- split_polys pols -;
  BIND deps <- build_dependency_matrix n (map fst spl) -;
  BIND indices <- topo_sort deps -;
  pure (map (fun t => nth t spl (nil, nil)) indices).

Lemma split_and_sort_index_NoDup :
  forall n pols, WHEN out <- split_and_sort n pols THEN forall polpl, In polpl out -> NoDup (snd polpl).
Proof.
  intros n pols out Hout polpl Hin.
  unfold split_and_sort in Hout.
  bind_imp_destruct Hout spl Hspl; bind_imp_destruct Hout deps Hdeps; bind_imp_destruct Hout indices Hindices; apply mayReturn_pure in Hout; rewrite <- Hout in *.
  rewrite in_map_iff in Hin. destruct Hin as [t [Hpolpl _]].
  destruct (t <? length spl)%nat eqn:Ht; reflect.
  - eapply nth_In in Ht; rewrite Hpolpl in Ht.
    eapply split_polys_index_NoDup in Ht; eauto.
  - eapply nth_overflow in Ht; rewrite Hpolpl in Ht.
    rewrite Ht; simpl. constructor.
Qed.

Lemma split_and_sort_index_correct :
  forall n pols, WHEN out <- split_and_sort n pols THEN forall polpl i, In polpl out -> In i (snd polpl) -> (i < length pols)%nat.
Proof.
  intros n pols out Hout polpl i Hin Hiin.
  unfold split_and_sort in Hout.
  bind_imp_destruct Hout spl Hspl; bind_imp_destruct Hout deps Hdeps; bind_imp_destruct Hout indices Hindices; apply mayReturn_pure in Hout; rewrite <- Hout in *.
  rewrite in_map_iff in Hin. destruct Hin as [t [Hpolpl _]].
  destruct (t <? length spl)%nat eqn:Ht; reflect.
  - eapply nth_In in Ht; rewrite Hpolpl in Ht.
    eapply split_polys_index_correct in Ht; eauto.
  - eapply nth_overflow in Ht; rewrite Hpolpl in Ht.
    rewrite Ht in Hiin; simpl in Hiin; tauto.
Qed.

Lemma split_and_sort_nrl :
  forall n pols, WHEN out <- split_and_sort n pols THEN forall k, (forall pol, In pol pols -> (poly_nrl pol <= k)%nat) -> (forall ppl, In ppl out -> (poly_nrl (fst ppl) <= k)%nat).
Proof.
  intros n pols out Hout k Hk ppl Hin.
  unfold split_and_sort in Hout.
  bind_imp_destruct Hout spl Hspl; bind_imp_destruct Hout deps Hdeps; bind_imp_destruct Hout indices Hindices; apply mayReturn_pure in Hout; rewrite <- Hout in *.
  rewrite in_map_iff in Hin. destruct Hin as [t [Hppl _]].
  destruct (t <? length spl)%nat eqn:Ht; reflect.
  - eapply nth_In in Ht; rewrite Hppl in Ht.
    eapply split_polys_nrl in Ht; eauto.
  - eapply nth_overflow in Ht; rewrite Hppl in Ht.
    rewrite Ht. unfold poly_nrl; simpl. lia.
Qed.

Lemma split_and_sort_disjoint :
  forall n pols, WHEN out <- split_and_sort n pols THEN
          forall p k1 k2 ppl1 ppl2, nth_error out k1 = Some ppl1 -> nth_error out k2 = Some ppl2 ->
                               in_poly p (fst ppl1) = true -> in_poly p (fst ppl2) = true -> k1 = k2.
Proof.
  intros n pols out Hout p k1 k2 ppl1 ppl2 Hk1 Hk2 Hp1 Hp2.
  unfold split_and_sort in Hout.
  bind_imp_destruct Hout spl Hspl; bind_imp_destruct Hout deps Hdeps; bind_imp_destruct Hout indices Hindices; apply mayReturn_pure in Hout; rewrite <- Hout in *.
  rewrite nth_error_map_iff in Hk1, Hk2.
  destruct Hk1 as [t1 [Hind1 Ht1]]; destruct Hk2 as [t2 [Hind2 Ht2]].
  symmetry in Ht1; rewrite <- nth_error_nth_iff in Ht1 by (
    erewrite <- map_length, <- build_dependency_matrix_length; [|eauto];
    eapply topo_sort_indices_correct; [eauto|]; apply nth_error_In in Hind1; eauto
  ).
  symmetry in Ht2; rewrite <- nth_error_nth_iff in Ht2 by (
    erewrite <- map_length, <- build_dependency_matrix_length; [|eauto];
    eapply topo_sort_indices_correct; [eauto|]; apply nth_error_In in Hind2; eauto
  ).
  assert (t1 = t2) by (eapply split_polys_disjoint; try (apply map_nth_error); eauto).
  eapply NoDup_nth_error; [|apply nth_error_Some; rewrite Hind1; congruence|congruence].
  eapply Permutation_NoDup; [apply topo_sort_permutation; eauto|apply n_range_NoDup].
Qed.  

Lemma split_and_sort_cover :
  forall n pols, WHEN out <- split_and_sort n pols THEN
            forall p pol i, nth_error pols i = Some pol -> in_poly p pol = true -> exists ppl, In ppl out /\ In i (snd ppl) /\ in_poly p (fst ppl) = true.
Proof.
  intros n pols out Hout p pol i Hi Hp.
  unfold split_and_sort in Hout.
  bind_imp_destruct Hout spl Hspl; bind_imp_destruct Hout deps Hdeps; bind_imp_destruct Hout indices Hindices; apply mayReturn_pure in Hout; rewrite <- Hout in *.
  eapply split_polys_cover in Hi; [|eauto]. specialize (Hi Hp).
  destruct Hi as [ppl [Hin [Hiin Hp1]]]. exists ppl.
  split; [|auto].
  apply In_nth_error in Hin; destruct Hin as [k Hk].
  rewrite in_map_iff. exists k. split; [erewrite nth_error_nth; eauto|].
  eapply Permutation_in; [eapply topo_sort_permutation; eauto|].
  erewrite build_dependency_matrix_length, map_length; [|eauto].
  rewrite n_range_in. apply nth_error_Some. congruence.
Qed.

Lemma split_and_sort_sorted :
  forall n pols, WHEN out <- split_and_sort n pols THEN
            forall k1 k2 ppl1 ppl2, nth_error out k1 = Some ppl1 -> nth_error out k2 = Some ppl2 ->
                               (k1 < k2)%nat -> canPrecede n (fst ppl1) (fst ppl2).
Proof.
  intros n pols out Hout k1 k2 ppl1 ppl2 Hk1 Hk2 Hcmp.
  bind_imp_destruct Hout spl Hspl; bind_imp_destruct Hout deps Hdeps; bind_imp_destruct Hout indices Hindices; apply mayReturn_pure in Hout; rewrite <- Hout in *.
  rewrite nth_error_map_iff in Hk1, Hk2.
  destruct Hk1 as [t1 [Hind1 Ht1]]; destruct Hk2 as [t2 [Hind2 Ht2]].
  symmetry in Ht1; rewrite <- nth_error_nth_iff in Ht1 by (
    erewrite <- map_length, <- build_dependency_matrix_length; [|eauto];
    eapply topo_sort_indices_correct; [eauto|]; apply nth_error_In in Hind1; eauto
  ).
  symmetry in Ht2; rewrite <- nth_error_nth_iff in Ht2 by (
    erewrite <- map_length, <- build_dependency_matrix_length; [|eauto];
    eapply topo_sort_indices_correct; [eauto|]; apply nth_error_In in Hind2; eauto
  ).
  assert (Hcmp2 : (k1 < k2 < length deps)%nat) by (split; [auto|]; rewrite <- topo_sort_length, <- nth_error_Some; [|eauto]; congruence).
  eapply topo_sort_sorted in Hcmp2; [|eauto].
  erewrite nth_error_nth with (n := k1) in Hcmp2; [|eauto].
  erewrite nth_error_nth with (n := k2) in Hcmp2; [|eauto].
  eapply build_dependency_matrix_canPrecede; [eauto| | |eauto]; erewrite map_nth_error; eauto.
Qed.

Definition make_npis pis pol pl :=
  map (fun t => let pi := nth t pis dummy_pi in
             let npol := poly_inter_pure pi.(pi_poly) pol in
             update_poly pi npol) pl.

Definition make_npis_simplify pis pol pl :=
  mapM (fun t => let pi := nth t pis dummy_pi in
              BIND npol <- poly_inter pi.(pi_poly) pol -;
              pure (update_poly pi npol)) pl.

Definition pi_equiv pi1 pi2 :=
  (forall p, in_poly p pi1.(pi_poly) = in_poly p pi2.(pi_poly)) /\
  pi1.(pi_instr) = pi2.(pi_instr) /\
  pi1.(pi_transformation) = pi2.(pi_transformation).

Lemma make_npis_simplify_equiv :
  forall pis pol pl,
    WHEN npis <- make_npis_simplify pis pol pl THEN
         Forall2 pi_equiv (make_npis pis pol pl) npis.
Proof.
  intros pis pol pl npis Hnpis.
  apply mapM_mayReturn in Hnpis.
  unfold make_npis. rewrite Forall2_map_left.
  eapply Forall2_imp; [|exact Hnpis].
  intros t pi Hpi. simpl in *.
  bind_imp_destruct Hpi npol Hnpol; apply mayReturn_pure in Hpi.
  rewrite <- Hpi in *.
  unfold pi_equiv, update_poly; simpl.
  split; [|tauto].
  intros p. symmetry. apply poly_inter_def. auto.
Qed.

Fixpoint generate_loop_many (d : nat) (n : nat) (pis : list Polyhedral_Instruction) : imp poly_stmt :=
  match d with
  | O => pure (make_seq (map (fun pi => PGuard pi.(pi_poly) (PInstr pi.(pi_instr) (map (fun t => (1%positive, t)) pi.(pi_transformation)))) pis))
  | S d1 =>
    BIND projs <- mapM (fun pi => project ((n - d1)%nat, pi.(pi_poly))) pis -;
    BIND projsep <- split_and_sort (n - d)%nat projs -;
    BIND inner <- mapM (fun '(pol, pl) =>
         BIND npis <- make_npis_simplify pis pol pl -;
         BIND inside <- generate_loop_many d1 n npis -;
         pure (PLoop pol inside)) projsep -;
    pure (make_seq inner)
  end.

Definition pis_have_dimension pis n :=
  forallb (fun pi => (poly_nrl (pi.(pi_poly)) <=? n)%nat) pis = true.

Lemma make_npis_simplify_have_dimension :
  forall pis pol pl n,
    pis_have_dimension pis n ->
    (poly_nrl pol <= n)%nat ->
    WHEN npis <- make_npis_simplify pis pol pl THEN
         pis_have_dimension npis n.
Proof.
  intros pis pol pl n Hpis Hpol npis Hnpis.
  unfold pis_have_dimension in *; rewrite forallb_forall in *.
  intros npi Hnpi. eapply mapM_in_iff in Hnpi; [|exact Hnpis].
  destruct Hnpi as [t [Hnpi Htin]].
  bind_imp_destruct Hnpi npol Hnpol. apply mayReturn_pure in Hnpi.
  reflect.
  rewrite <- Hnpi; simpl.
  eapply poly_inter_nrl; [|exact Hpol|exact Hnpol].
  destruct (t <? length pis)%nat eqn:Ht; reflect.
  - specialize (Hpis (nth t pis dummy_pi)). reflect; apply Hpis.
    apply nth_In; auto.
  - rewrite nth_overflow by auto.
    simpl. unfold poly_nrl; simpl. lia.
Qed.

Definition generate_invariant (n : nat) (pis : list Polyhedral_Instruction) (env : list Z) :=
  (* forall pi, In pi pis -> project_invariant n pi.(pi_poly) (rev env). *)
  True.

Lemma project_inclusion2 :
  forall (n : nat) (p : list Z) (pol : list (list Z * Z)),
    in_poly p pol = true -> WHEN proj <- project (n, pol) THEN in_poly p proj = true.
Proof.
  intros n p pol Hin proj Hproj.
  generalize (project_inclusion n p pol Hin proj Hproj); intros H.
  unfold in_poly in *; rewrite forallb_forall in *. intros c Hc; specialize (H c Hc).
  apply project_constraint_size with (c := c) in Hproj. specialize (Hproj Hc).
  rewrite <- H; unfold satisfies_constraint; f_equal.
  rewrite Hproj, <- dot_product_resize_left, resize_length.
  reflexivity.
Qed.

(* Useful to weaken an hypothesis in next proof *)
Lemma refl_scan :
  forall (scan1 scan2 : nat -> list Z -> bool), scan1 = scan2 -> (forall n p, scan1 n p = scan2 n p).
Proof.
  intros scan1 scan2 ->. reflexivity.
Qed.

Lemma poly_lex_semantics_subpis :
  forall pis pl to_scan mem1 mem2,
    (forall n p, to_scan n p = true -> In n pl) ->
    NoDup pl ->
    (forall n, In n pl -> (n < length pis)%nat) ->
    poly_lex_semantics to_scan pis mem1 mem2 <->
    poly_lex_semantics (fun n p => match nth_error pl n with Some m => to_scan m p | None => false end) (map (fun t => nth t pis dummy_pi) pl) mem1 mem2.
Proof.
  intros pis pl to_scan mem1 mem2 Hscan Hdup Hpl.
  split.
  - intros H; induction H as [to_scan prog mem Hdone|to_scan prog mem1 mem2 mem3 pi n p Hscanp Heqpi Hts Hsem1 Hsem2 IH].
    + apply PolyLexDone. intros n p; destruct (nth_error pl n); auto.
    + generalize (Hscan _ _ Hscanp); intros Hnpl. apply In_nth_error in Hnpl; destruct Hnpl as [k Hk].
      eapply PolyLexProgress; [| | |exact Hsem1|eapply poly_lex_semantics_extensionality; [apply IH|]].
      * rewrite Hk; auto.
      * erewrite map_nth_error; [|exact Hk]. f_equal.
        apply nth_error_nth; auto.
      * intros n2 p2 H; destruct (nth_error pl n2); auto.
      * intros n2 p2 H; eapply Hscan.
        unfold scanned in H; reflect; destruct H; eauto.
      * auto.
      * intros k2 p2. unfold scanned. simpl.
        destruct (nth_error pl k2) as [n2|] eqn:Hk2; simpl; [|reflexivity].
        f_equal. f_equal. f_equal.
        apply eq_iff_eq_true; reflect.
        split; [|congruence]. intros Hn. rewrite NoDup_nth_error in Hdup. apply Hdup; [|congruence].
        rewrite <- nth_error_Some. congruence.
  - match goal with [ |- poly_lex_semantics ?x ?y _ _ -> _] => remember x as to_scan1; remember y as pis1 end.
    generalize (refl_scan _ _ Heqto_scan1); clear Heqto_scan1; intros Heqto_scan1.
    intros H; generalize to_scan1 pis1 H to_scan Hscan Heqto_scan1 Heqpis1. clear Heqto_scan1 Heqpis1 Hscan to_scan H pis1 to_scan1.
    intros to_scan1 pis1 H.
    induction H as [to_scan1 prog mem Hdone|to_scan1 prog mem1 mem2 mem3 pi n p Hscanp Heqpi Hts Hsem1 Hsem2 IH].
    + intros; apply PolyLexDone.
      intros n p.
      apply not_true_is_false. intros Hscan2.
      destruct (In_nth_error _ _ (Hscan _ _ Hscan2)) as [k Hk].
      specialize (Heqto_scan1 k p). rewrite Hdone, Hk in Heqto_scan1. congruence.
    + intros to_scan Hscan Hscan1 Hprog; rewrite Hprog in *; rewrite Hscan1 in *.
      destruct (nth_error pl n) as [k|] eqn:Hk; [|congruence].
      eapply PolyLexProgress; [exact Hscanp| | |exact Hsem1|eapply poly_lex_semantics_extensionality; [apply (IH (scanned to_scan k p))|]].
      * erewrite map_nth_error in Heqpi; [|exact Hk].
        rewrite nth_error_nth_iff with (d := dummy_pi); [congruence|eauto].
      * intros n2 p2 Hts2. apply not_true_is_false. intros Hscan2.
        destruct (In_nth_error _ _ (Hscan _ _ Hscan2)) as [k2 Hk2].
        specialize (Hts k2 p2 Hts2); rewrite Hscan1, Hk2 in Hts. congruence.
      * intros n2 p2 H. unfold scanned in H. reflect. destruct H; eapply Hscan; eauto.
      * intros n2 p2. unfold scanned. simpl. rewrite Hscan1.
        destruct (nth_error pl n2) as [k2|] eqn:Hk2; simpl; [|reflexivity].
        f_equal. f_equal. f_equal.
        apply eq_iff_eq_true; reflect.
        split; [congruence|]. intros Hn. rewrite NoDup_nth_error in Hdup. apply Hdup; [|congruence].
        rewrite <- nth_error_Some. congruence.
      * reflexivity.
      * reflexivity.
Qed. 

Lemma env_scan_pi_equiv :
  forall env pis1 pis2 d n p,
    Forall2 pi_equiv pis1 pis2 ->
    env_scan pis1 env d n p = env_scan pis2 env d n p.
Proof.
  intros env pis1 pis2 d n p H.
  unfold env_scan. destruct (nth_error pis1 n) as [pi1|] eqn:Hpi1.
  - destruct (Forall2_nth_error _ _ _ _ _ _ _ H Hpi1) as [pi2 [-> Hpis]].
    f_equal. unfold pi_equiv in Hpis. destruct Hpis; auto.
  - erewrite nth_error_None, Forall2_length, <- nth_error_None in Hpi1 by (exact H).
    rewrite Hpi1; reflexivity.
Qed.

Lemma env_poly_lex_semantics_ext_pi_equiv :
  forall env n pis1 pis2 mem1 mem2,
    Forall2 pi_equiv pis1 pis2 ->
    env_poly_lex_semantics env n pis1 mem1 mem2 <-> env_poly_lex_semantics env n pis2 mem1 mem2.
Proof.
  intros env n pis1 pis2 mem1 mem2 H.
  unfold env_poly_lex_semantics.
  rewrite poly_lex_semantics_pis_ext_iff; [rewrite poly_lex_semantics_ext_iff; [reflexivity|]|].
  - intros m p. apply env_scan_pi_equiv. auto.
  - eapply Forall2_imp; [|exact H]. intros; unfold pi_equiv in *; tauto.
Qed.

Definition subscan pis pol pl env d n p :=
  existsb (fun m => (m =? n)%nat) pl && in_poly p pol && env_scan pis env d n p.

Lemma subscan_in :
  forall pis pol pl env d n p,
    subscan pis pol pl env d n p = true -> in_poly p pol = true.
Proof.
  intros pis pol pl env d n p Hsub.
  unfold subscan in Hsub.
  reflect; tauto.
Qed.

Lemma subscan_in_env :
  forall pis pol pl env d n p,
    (poly_nrl pol <= S (length env))%nat ->
    subscan pis pol pl env d n p = true ->
    in_poly (env ++ (nth (length env) p 0) :: nil) pol = true.
Proof.
  intros pos pol pl env d n p Hnrl Hsub.
  unfold subscan in Hsub. reflect. destruct Hsub as [[_ Hpin] Hscan].
  apply env_scan_begin in Hscan. rewrite Hscan in Hpin.
  erewrite <- in_poly_nrlength by (exact Hnrl).
  erewrite <- in_poly_nrlength in Hpin by (exact Hnrl).
  rewrite resize_app_le in * by lia.
  replace (S (length env) - length env)%nat with 1%nat in * by lia.
  rewrite resize_1 in *. simpl.
  rewrite nth_skipn, Nat.add_0_r in Hpin. auto.
Qed.

Instance subscan_proper pis pol pl env d : Proper (eq ==> veq ==> eq) (subscan pis pol pl env d).
Proof.
  intros n1 n2 Hn p1 p2 Hp. unfold subscan.
  rewrite Hn, Hp. reflexivity.
Qed.

Lemma poly_lex_semantics_make_npis_subscan :
  forall pis pol pl n env mem1 mem2,
    NoDup pl ->
    (forall n, In n pl -> (n < length pis)%nat) ->
    poly_lex_semantics (subscan pis pol pl (rev env) n) pis mem1 mem2 <->
    env_poly_lex_semantics (rev env) n (make_npis pis pol pl) mem1 mem2.
Proof.
  intros pis pol pl n env mem1 mem2 Hdup Hind.
  unfold env_poly_lex_semantics, make_npis. 
  rewrite poly_lex_semantics_subpis with (pl := pl).
  - erewrite poly_lex_semantics_pis_ext_iff; [apply poly_lex_semantics_ext_iff|].
    + intros m p. destruct (nth_error pl m) as [k|] eqn:Hk.
      * assert (Hkin : In k pl) by (eapply nth_error_In; eauto).
        unfold subscan, env_scan. erewrite map_nth_error; [|exact Hk]. simpl.
        rewrite poly_inter_pure_def.
        destruct (nth_error pis k) as [pi|] eqn:Hpik; [|rewrite nth_error_None in Hpik; specialize (Hind _ Hkin); lia].
        erewrite nth_error_nth; [|exact Hpik].
        replace (existsb (fun k1 => (k1 =? k)%nat) pl) with true by (symmetry; rewrite existsb_exists; exists k; reflect; auto).
        ring.
      * rewrite nth_error_None in Hk. unfold env_scan.
        erewrite <- map_length, <- nth_error_None in Hk; rewrite Hk.
        reflexivity.
    + rewrite Forall2_map_left, Forall2_map_right. apply Forall2_R_refl.
      intros x; simpl; auto.
  - intros m p Hscan. unfold subscan in Hscan.
    destruct (existsb (fun m1 => (m1 =? m)%nat) pl) eqn:Hex; simpl in *; [|congruence].
    rewrite existsb_exists in Hex; destruct Hex as [m1 [Hm1 Hmeq]]. reflect.
    rewrite <- Hmeq; auto.
  - auto.
  - auto.
Qed.

Lemma env_scan_extend_many :
  forall d n pis lb ub env m p,
    length env = n ->
    (n < d)%nat ->
    (forall x, env_scan pis (rev env ++ x :: nil) d m p = true -> lb <= x < ub) ->
    env_scan pis (rev env) d m p =
      existsb (fun x : Z => env_scan pis (rev env ++ x :: nil) d m p) (Zrange lb ub).
Proof.
  intros d n pis lb ub env m p Hlen Hnd Hlbub.
  rewrite eq_iff_eq_true. rewrite existsb_exists.
  rewrite env_scan_split by (rewrite rev_length; lia).
  split.
  - intros [x Hscan]; exists x; split; [|auto].
    rewrite Zrange_in. auto.
  - intros [x [H1 H2]]; exists x; assumption.
Qed.

Lemma env_scan_make_npis_in :
  forall pis pol pl env n m p,
    env_scan (make_npis pis pol pl) env n m p = true -> in_poly p pol = true.
Proof.
  intros pis pol pl env n m p H.
  unfold make_npis, env_scan in H.
  destruct nth_error as [pi|] eqn:Hpi; [|congruence].
  rewrite nth_error_map_iff in Hpi. destruct Hpi as [t [Ht Hpi]].
  rewrite Hpi in H; simpl in H.
  rewrite poly_inter_pure_def in H. reflect; tauto.
Qed.

Theorem generate_loop_many_preserves_sem :
  forall d n pis env mem1 mem2,
    (d <= n)%nat ->
    WHEN st <- generate_loop_many d n pis THEN
    poly_loop_semantics st env mem1 mem2 ->
    length env = (n - d)%nat ->
    pis_have_dimension pis n ->
    generate_invariant (n - d)%nat pis env ->
    env_poly_lex_semantics (rev env) n pis mem1 mem2.
Proof.
  induction d.
  - intros n pis env mem1 mem2 Hnd st Hgen Hsem Hlen Hpidim Hinv.
    simpl in *. apply mayReturn_pure in Hgen. rewrite <- Hgen in Hsem.
    apply make_seq_semantics in Hsem.
    unfold env_poly_lex_semantics.
    rewrite iter_semantics_mapl in Hsem.
    rewrite iter_semantics_combine with (ys := n_range (length pis)) in Hsem by (rewrite n_range_length; auto).
    eapply poly_lex_semantics_extensionality;
      [eapply poly_lex_concat_seq with (to_scans := fun (arg : Polyhedral_Instruction * nat) m p => (m =? snd arg)%nat && env_scan pis (rev env) n m p)|].
    + eapply iter_semantics_map; [|exact Hsem].
      intros [pi x] mem3 mem4 Hinpixs Hloopseq. simpl in *.
      rewrite combine_n_range_in in Hinpixs.
      apply PLGuard_inv_sem in Hloopseq.
      destruct (in_poly (rev env) (pi_poly pi)) eqn:Hinpi;
        [apply PLInstr_inv_sem in Hloopseq; eapply PolyLexProgress with (p := rev env); [|exact Hinpixs| | |apply PolyLexDone]|].
      * unfold env_scan. rewrite Hinpixs. reflect. split; [auto|].
        split; [rewrite !resize_length_eq; [split; reflexivity| |]; rewrite !rev_length; lia|].
        exact Hinpi.
      * intros n2 p2 H. destruct (n2 =? x)%nat eqn:Hn2; reflect; [|auto].
        right. apply not_true_is_false; intros Hscan.
        apply env_scan_single in Hscan; [|rewrite rev_length; lia].
        rewrite Hscan in H. rewrite lex_compare_reflexive in H; congruence.
      * rewrite map_map in Hloopseq. unfold affine_product.
        erewrite map_ext; [exact Hloopseq|].
        intros c; unfold eval_affine_expr; simpl. rewrite Z.div_1_r. reflexivity.
      * intros m p. unfold scanned.
        apply not_true_is_false. intros H; reflect.
        destruct H as [[Hmx Hscan] H].
        apply env_scan_single in Hscan; [|rewrite rev_length; lia].
        rewrite Hscan, is_eq_reflexive in H. destruct H; congruence.
      * rewrite Hloopseq; apply PolyLexDone. intros m p. apply not_true_is_false. intros H; reflect. destruct H as [Hmx Hscan].
        assert (H : rev env =v= p) by (apply env_scan_single in Hscan; [|rewrite rev_length; lia]; auto). rewrite H in Hinpi.
        unfold env_scan in Hscan; rewrite Hmx, Hinpixs, Hinpi in Hscan. reflect; destruct Hscan; congruence.
    + intros [i x] m1 m2 -> p1 p2 ->. reflexivity.
    + intros [i1 x1] k1 [i2 x2] k2 m p H1 H2 Hk1 Hk2.
      rewrite nth_error_combine in Hk1, Hk2. simpl in *; reflect.
      rewrite n_range_nth_error in Hk1, Hk2. destruct H1; destruct H2; destruct Hk1 as [? [? ?]]; destruct Hk2 as [? [? ?]]. congruence.
    + intros [i1 x1] n1 p1 k1 [i2 x2] n2 p2 k2 Hcmp H1 H2 Hk1 Hk2.
      reflect; simpl in *.
      rewrite nth_error_combine, n_range_nth_error in Hk1, Hk2.
      destruct H1 as [Hn1 H1]; destruct H2 as [Hn2 H2].
      apply env_scan_single in H1; apply env_scan_single in H2; try (rewrite rev_length; lia).
      rewrite <- H1, <- H2, lex_compare_reflexive in Hcmp. congruence.
    + intros m p. simpl. rewrite eq_iff_eq_true, existsb_exists.
      split; [intros [x Hx]; reflect; tauto|]. intros Hscan; rewrite Hscan.
      unfold env_scan in Hscan. destruct (nth_error pis m) as [pi|] eqn:Hpi; [|congruence].
      exists (pi, m). rewrite combine_n_range_in.
      simpl in *; reflect; auto.
  - intros n pis env mem1 mem2 Hnd st Hgen Hsem Hlen Hpidim Hinv. simpl in *.
    bind_imp_destruct Hgen projs Hprojs.
    bind_imp_destruct Hgen projsep Hprojsep.
    bind_imp_destruct Hgen inner Hinner.
    assert (Hprojnrl : forall ppl, In ppl projsep -> (poly_nrl (fst ppl) <= n - d)%nat).
    {
      eapply split_and_sort_nrl; [eauto|].
      intros pol Hpolin. eapply mapM_in_iff in Hpolin; [|eauto].
      destruct Hpolin as [pi [Hpol Hpiin]].
      rewrite <- poly_nrl_def. intros c; eapply project_constraint_size; eauto.
    }
    apply mayReturn_pure in Hgen. rewrite <- Hgen in Hsem; clear Hgen.
    rewrite make_seq_semantics in Hsem.
    unfold env_poly_lex_semantics.
    eapply poly_lex_semantics_extensionality;
      [apply poly_lex_concat_seq with (to_scans := fun (arg : (polyhedron * list nat * poly_stmt)) => subscan pis (fst (fst arg)) (snd (fst arg)) (rev env) n)|].
    + eapply iter_semantics_mapM_rev in Hsem; [|exact Hinner].
      eapply iter_semantics_map; [|apply Hsem]. clear Hsem.
      intros [[pol pl] inner1] mem3 mem4 Hins [Hinner1 Hseminner1].
      apply in_combine_l in Hins.
      bind_imp_destruct Hinner1 npis Hnpis.
      bind_imp_destruct Hinner1 inside Hinside.
      apply mayReturn_pure in Hinner1; rewrite <- Hinner1 in *.
      simpl. rewrite poly_lex_semantics_make_npis_subscan; [|
        eapply split_and_sort_index_NoDup with (polpl := (pol, pl)); eauto |
        intros i Hi; erewrite mapM_length; [|exact Hprojs]; eapply split_and_sort_index_correct with (polpl := (pol, pl)); eauto
      ].
      erewrite env_poly_lex_semantics_ext_pi_equiv; [|apply make_npis_simplify_equiv; eauto].
      apply PLLoop_inv_sem in Hseminner1.
      destruct Hseminner1 as [lb [ub [Hlbub Hsem]]].
      unfold env_poly_lex_semantics in *.
      eapply poly_lex_semantics_extensionality.
      apply poly_lex_concat_seq with (to_scans := fun x => env_scan npis (rev (x :: env)) n).
      * eapply iter_semantics_map; [|apply Hsem].
        intros x mem5 mem6 Hbounds Hloop. eapply IHd with (env := x :: env); simpl; eauto; try lia.
        -- eapply make_npis_simplify_have_dimension; eauto.
           specialize (Hprojnrl _ Hins). simpl in Hprojnrl; lia.
        (* no longer needed: generate_invariant is [True] now.
        -- unfold generate_invariant in *. (* generate_invariant preservation *)
           intros npi Hnpi. eapply mapM_in_iff in Hnpi; [|eauto].
           destruct Hnpi as [t [Hnpi Ht]]. remember (nth t pis dummy_pi) as pi. simpl in Hnpi.
           assert (Hpi : In pi pis). {
             rewrite Heqpi; apply nth_In. erewrite mapM_length; eauto.
             eapply split_and_sort_index_correct; eauto.
           }
         *)
      * intros x; apply env_scan_proper.
      * intros x1 k1 x2 k2 m p H1 H2 H3 H4. rewrite Zrange_nth_error in *.
        enough (lb + Z.of_nat k1 = lb + Z.of_nat k2) by lia.
        eapply env_scan_inj_rev; [destruct H3 as [? <-]; exact H1|destruct H4 as [? <-]; exact H2].
      * intros x1 n1 p1 k1 x2 n2 p2 k2 Hcmp H1 H2 H3 H4.
        rewrite Zrange_nth_error in *.
        apply env_scan_begin in H1; apply env_scan_begin in H2. simpl in *.
        rewrite H1, H2 in Hcmp.
        enough (lb + Z.of_nat k2 <= lb + Z.of_nat k1) by lia.
        eapply lex_app_not_gt.
        destruct H3 as [? <-]; destruct H4 as [? <-].
        rewrite Hcmp; congruence.
      * simpl. intros m p.
        erewrite env_scan_extend_many; [reflexivity|exact Hlen|lia|].
        intros x Hscanx. apply Hlbub; simpl.
        erewrite <- env_scan_pi_equiv in Hscanx; [|apply make_npis_simplify_equiv; eauto].
        assert (Hpin : in_poly p pol = true) by (eapply env_scan_make_npis_in; eauto).
        rewrite env_scan_begin in Hpin by (exact Hscanx).
        erewrite <- in_poly_nrlength in Hpin; [|exact (Hprojnrl _ Hins)].
        rewrite resize_app in Hpin; [auto|].
        rewrite app_length, rev_length. simpl. lia.
    + intros. apply subscan_proper.
    + intros [[pol1 pl1] inner1] k1 [[pol2 pl2] inner2] k2 m p Hscan1 Hscan2 Hnth1 Hnth2.
      rewrite nth_error_combine in Hnth1, Hnth2. simpl in *.
      destruct Hnth1 as [Hnth1 _]; destruct Hnth2 as [Hnth2 _].
      apply subscan_in in Hscan1; apply subscan_in in Hscan2.
      eapply split_and_sort_disjoint; eauto.
    + intros [[pol1 pl1] inner1] m1 p1 k1 [[pol2 pl2] inner2] m2 p2 k2 Hcmp Hscan1 Hscan2 Hnth1 Hnth2.
      rewrite nth_error_combine in Hnth1, Hnth2. simpl in *.
      destruct Hnth1 as [Hnth1 _]; destruct Hnth2 as [Hnth2 _].
      rewrite env_scan_begin with (p := p1) in Hcmp by (unfold subscan in Hscan1; reflect; destruct Hscan1; eauto).
      rewrite env_scan_begin with (p := p2) in Hcmp by (unfold subscan in Hscan2; reflect; destruct Hscan2; eauto).
      apply subscan_in_env in Hscan1; [|rewrite rev_length; apply nth_error_In in Hnth1; specialize (Hprojnrl _ Hnth1); simpl in *; lia].
      apply subscan_in_env in Hscan2; [|rewrite rev_length; apply nth_error_In in Hnth2; specialize (Hprojnrl _ Hnth2); simpl in *; lia].
      rewrite lex_compare_app, lex_compare_reflexive in Hcmp by auto.
      destruct (k2 <=? k1)%nat eqn:Hprec; reflect; [auto|exfalso].
      eapply split_and_sort_sorted in Hprec; eauto. simpl in Hprec.
      unfold canPrecede in Hprec.
      specialize (Hprec _ (nth (length (rev env)) p2 0) Hscan1).
      rewrite assign_app_ge, app_nth2 in Hprec by (rewrite rev_length; lia).
      rewrite rev_length, Hlen, Nat.sub_diag in Hprec.
      rewrite rev_length, Hlen in Hscan1, Hscan2, Hcmp.
      specialize (Hprec Hscan2). simpl in Hprec.
      apply lex_compare_lt_head in Hcmp. rewrite !nth_skipn, !Nat.add_0_r in Hcmp.
      lia.
    + intros m p. simpl.
      apply eq_iff_eq_true. rewrite existsb_exists. split.
      * intros [[[pol pl] inner1] [Hin Hsubscan]].
        unfold subscan in Hsubscan. reflect. tauto.
      * intros Hscan.
        enough (exists x, In x projsep /\ subscan pis (fst x) (snd x) (rev env) n m p = true).
        {
          destruct H as [polpl [Hin Hsub]].
          eapply in_l_combine in Hin; [|eapply mapM_length; exact Hinner].
          destruct Hin as [inner1 Hin].
          exists (polpl, inner1); simpl; tauto.
        }
        unfold subscan.
        rewrite Hscan.
        unfold env_scan in Hscan. destruct (nth_error pis m) as [pi|] eqn:Hpi; [|congruence].
        reflect.
        destruct (mapM_nth_error2 _ _ _ _ _ _ Hpi _ Hprojs) as [pol [Hproj Hpol]].
        destruct Hscan as [[_ Hpresize] Hpin].
        generalize (project_inclusion2 _ _ _ Hpin _ Hproj). intros Hpin2.
        destruct (split_and_sort_cover _ _ _ Hprojsep _ _ _ Hpol Hpin2) as [ppl [Hpplin [Hppl1 Hppl2]]].
        exists ppl. split; [auto|].
        reflect; split; [|auto]; split; auto.
        rewrite existsb_exists; exists m; reflect; auto.
Qed.

Fixpoint ctx_simplify pol ctx :=
  match pol with
  | nil => pure nil
  | c :: pol =>
    BIND simp1 <- ctx_simplify pol ctx -;
    BIND b <- isBottom (neg_constraint c :: simp1 ++ ctx) -;
    pure (if b then simp1 else c :: simp1)
  end.

Lemma ctx_simplify_correct :
  forall pol ctx, WHEN simp <- ctx_simplify pol ctx THEN (forall p, in_poly p ctx = true -> in_poly p pol = in_poly p simp).
Proof.
  induction pol; intros ctx simp Hsimp p Hpctx; simpl in *.
  - apply mayReturn_pure in Hsimp; rewrite <- Hsimp; reflexivity.
  - bind_imp_destruct Hsimp simp1 Hsimp1; bind_imp_destruct Hsimp b Hb; apply mayReturn_pure in Hsimp; rewrite <- Hsimp in *.
    transitivity (satisfies_constraint p a && in_poly p simp1); [f_equal; eapply IHpol; eauto|].
    destruct b; simpl; [|auto].
    apply isBottom_correct_1 in Hb; specialize (Hb p); simpl in *.
    rewrite neg_constraint_correct in Hb.
    destruct (satisfies_constraint p a); [auto|]. simpl in *.
    rewrite in_poly_app, Hpctx, andb_true_r in Hb. auto.
Qed.

Fixpoint polyloop_simplify stmt n ctx :=
  match stmt with
  | PSkip => pure PSkip
  | PSeq st1 st2 => BIND s1 <- polyloop_simplify st1 n ctx -; BIND s2 <- polyloop_simplify st2 n ctx -; pure (PSeq s1 s2)
  | PGuard pol st =>
    let pol := resize_poly n pol in
    BIND npol <- ctx_simplify pol ctx -;
    BIND nctx <- poly_inter pol ctx -;
    BIND nst <- polyloop_simplify st n nctx -;
    pure (PGuard npol nst)
  | PLoop pol st =>
    let pol := resize_poly (S n) pol in
    BIND npol <- ctx_simplify pol ctx -;
    BIND nctx <- poly_inter pol ctx -;
    BIND nst <- polyloop_simplify st (S n) nctx -;
    pure (PLoop npol nst)
  | PInstr i es => pure (PInstr i es)
  end.


Lemma polyloop_simplify_correct :
  forall stmt n ctx,
    (poly_nrl ctx <= n)%nat ->
    WHEN nst <- polyloop_simplify stmt n ctx THEN
         forall env mem1 mem2, length env = n -> in_poly (rev env) ctx = true ->
                          poly_loop_semantics nst env mem1 mem2 ->
                          poly_loop_semantics stmt env mem1 mem2.
Proof.
  induction stmt; intros n ctx Hctx nst Hnst env mem1 mem2 Henvlen Henvctx Hsem; simpl in *.
  - bind_imp_destruct Hnst npol Hnpol; bind_imp_destruct Hnst nctx Hnctx.
    bind_imp_destruct Hnst nst1 Hnst1; apply mayReturn_pure in Hnst; rewrite <- Hnst in *.
    apply PLLoop_inv_sem in Hsem.
    assert (Hinctx : forall x, in_poly (rev (x :: env)) ctx = true) by
        (intros x; rewrite <- in_poly_nrlength with (n := n); [|auto]; simpl; rewrite resize_app by (rewrite rev_length; auto); auto).
    assert (Heq : forall x, in_poly (rev (x :: env)) npol = in_poly (rev (x :: env)) p) by
        (intros x; erewrite <- (ctx_simplify_correct _ _ _ Hnpol); [rewrite resize_poly_in; [|rewrite rev_length]; simpl; auto|auto]).
    destruct Hsem as [lb [ub [Hlbub Hsem]]].
    apply PLLoop with (lb := lb) (ub := ub); [intros x; rewrite <- Heq; apply Hlbub|].
    eapply iter_semantics_map; [|exact Hsem].
    intros x mem3 mem4 Hx Hsem1. simpl in *.
    rewrite Zrange_in, <- Hlbub, Heq in Hx.
    assert (Hnctxnrl : (poly_nrl nctx <= S n)%nat) by (eapply poly_inter_nrl; [apply resize_poly_nrl| |exact Hnctx]; lia).
    eapply IHstmt; [exact Hnctxnrl|exact Hnst1|simpl; auto| |exact Hsem1].
    erewrite poly_inter_def, poly_inter_pure_def, resize_poly_in; [|rewrite rev_length|exact Hnctx]; [|simpl; auto]; reflect; simpl; auto.
  - apply mayReturn_pure in Hnst; rewrite <- Hnst in *; auto.
  - apply mayReturn_pure in Hnst; rewrite <- Hnst in *; auto.
  - bind_imp_destruct Hnst s1 Hs1; bind_imp_destruct Hnst s2 Hs2; apply mayReturn_pure in Hnst; rewrite <- Hnst in *.
    apply PLSeq_inv_sem in Hsem; destruct Hsem as [mem3 [Hsem1 Hsem2]].
    apply PLSeq with (mem2 := mem3); [eapply IHstmt1 | eapply IHstmt2]; eauto.
  - bind_imp_destruct Hnst npol Hnpol; bind_imp_destruct Hnst nctx Hnctx.
    bind_imp_destruct Hnst nst1 Hnst1; apply mayReturn_pure in Hnst; rewrite <- Hnst in *.
    apply PLGuard_inv_sem in Hsem.
    replace (in_poly (rev env) npol) with (in_poly (rev env) p) in *.
    + destruct (in_poly (rev env) p) eqn:Hin.
      * apply PLGuardTrue; [|auto].
        assert (Henvnctx : in_poly (rev env) nctx = true) by
            (erewrite poly_inter_def, poly_inter_pure_def; [|exact Hnctx]; reflect; rewrite resize_poly_in; auto; rewrite rev_length; auto).
        assert (Hnctxnrl : (poly_nrl nctx <= n)%nat) by (eapply poly_inter_nrl; [apply resize_poly_nrl|exact Hctx|exact Hnctx]).
        eapply IHstmt with (n := n) (ctx := nctx); eauto.
      * rewrite Hsem. apply PLGuardFalse; auto.
    + erewrite <- (ctx_simplify_correct _ _ _ Hnpol); auto.
      rewrite resize_poly_in; [|rewrite rev_length]; auto.
Qed.


Definition complete_generate_many d n pis :=
  BIND polyloop <- generate_loop_many d n pis -;
  BIND simp <- polyloop_simplify polyloop (n - d)%nat nil -;
  polyloop_to_loop (n - d)%nat simp.

Theorem complete_generate_many_preserve_sem :
  forall d n pis env mem1 mem2,
    (d <= n)%nat ->
    WHEN st <- complete_generate_many d n pis THEN
    loop_semantics st env mem1 mem2 ->
    length env = (n - d)%nat ->
    pis_have_dimension pis n ->
    env_poly_lex_semantics (rev env) n pis mem1 mem2.
Proof.
  intros d n pis env mem1 mem2 Hdn st Hst Hloop Henv Hpis.
  unfold complete_generate_many in Hst.
  bind_imp_destruct Hst polyloop Hpolyloop; bind_imp_destruct Hst simp Hsimp.
  eapply generate_loop_many_preserves_sem; eauto; [|unfold generate_invariant; auto].
  eapply polyloop_simplify_correct; [|exact Hsimp| | |]; auto; [unfold poly_nrl; simpl; lia|].
  eapply polyloop_to_loop_correct; eauto.
Qed.
