# Installing dependencies

The Coq development requires Coq version 8.7.2 and OCaml between 4.05.0 and 4.07.1 and may not work with newer versions of Coq and OCaml.

You will need the bundled version of the Verimag Polyhedra Library, which you can get with:
```bash
git submodule init
git submodule update --recursive
```

Some additional C and OCaml libraries are required, as described below.

We recommend to use either OPAM (the OCaml package manager) or Nix (a Linux package manager).

## With OPAM 

Create a new OPAM switch: `opam switch create polygen 4.06.1+flambda`.
Install GMP, Debian/Ubuntu package libgmp-dev (GNU Multiple Precision Arithmetic Library)
Install GLPK, Debian/Ubuntu package libglpk-dev (GNU Linear Programming Kit)
Install [eigen](http://eigen.tuxfamily.org/), Debian/Ubuntu package libeigen3-dev.
Install the following ocaml packages: `opam install zarith glpk menhir coq=8.7.2`.

## With Nix

Another way is to use `nix`. Type `nix-shell` to get a shell where all dependencies have been downloaded and installed.
One way to install `nix` is:
```bash
curl https://nixos.org/nix/install | sh
```

Note that, if you use OPAM, the OPAM init scripts can add your current version of ocaml to your `$PATH`. In that case, it is advised to use
`nix-shell --pure`, which will run a shell where all dependencies have been downloaded and installed, but no other programs will be available,
avoiding the conflicts with a preexisting OPAM installation.

# Compiling

There are four steps for compiling the code:
* Setup the VPL: `make vplsetup`.
  This step compiles the bundled version of the Verimag Polyhedra Library that we use.
* Compile the Coq files: `make`.
* Extract the code generator to OCaml: `make extract`.
* Compile the extracted code: `make ocaml`.

The executable running the code generator on different tests will be in `ocaml/test`.  Just run `./ocaml/test`, the results will be displayed on standard output.

Alternatively, if using `nix`, you can just type `nix build`, and the executable will be available in `result/bin/test`.

You can build the documentation with `make documentation`, and it will be available in doc/index.html, or result/doc/index.html if you used `nix build`.

```
Table of contents
General-purpose libraries
Misc: Extensions to the Coq standard library.
Linalg: Definitions of vectors of integers and operations over them.
Result: The error monad.
TopoSort: Topological sort.
Mymap: Workaround for a bug in Coq.
ImpureOperations: Definition of operations over a monad (sequence and mapM).
ImpureAlarmConfig: Error monad used throughout the code.
Polyhedral operations
VplInterface: Conversion between our representation of polyhedra and the one used by the VPL.
Canonizer: Simplication of redundant constraints in polyhedra using the VPL.
Heuristics: Heuristics for some polyhedral operations.
Projection: Computation of polyhedral projections using Fourier-Motzkin elimination.
PolyTest: Operators that test over polyhedra: emptiness, inclusion, precedence (section 5 of the paper).
PolyOperations: Polyhedra operations: intersection, difference, splitting and sorting (section 5 of the paper), simplifying in a context (section 6 of the paper).
Languages and semantics
Semantics: Memory states, semantics for iterating over a list and associated theorems.
Instr: Semantics of base instructions.
PolyLang: Semantics of the scheduled polyhedral language, and proof of schedule elimination (sections 3 and 4 of the paper).
PolyLoop: Semantics of the PolyLoop language (section 5 of the paper).
Loop: Semantics of the Loop language (section 7 of the paper).
Compilation
ASTGen: Code generation from PolyLang to PolyLoop (section 5 of the paper).
PolyLoopSimpl: Simplification of PolyLoop programs (section 6 of the paper).
LoopGen: Code generation from PolyLoop to Loop (section 7 of the paper).
CodeGen: Proof of the main result by composing all passes.
```