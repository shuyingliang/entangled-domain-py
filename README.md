entangled-domain-py
===================

+ Description:

  The entangled abstract domain is built upon previous pyana project 
  using Z3 Racket binding to prove list  in bound for demonstration.

  There're two implementations routes, both are implemented in the way
  as the paper described: 
  
  + Concolic relational abstract domain (Conlic RAD):
    The main idea is to use concrete values validated by abstract interpretation (AI)
    This implementation has passed all the test cases.
    
  + The entangled abstract domain (entangled RAD):
    This one aims to use uninterpreted array to model list. Propositions are also
    managed and validated by AI. In addition, it uses per-state assumption base.
    Due to the imprecision of the premiere analysis model(CESK* machine), widening
    is applied here to speed up reaching fix-point. However, it still takes moments
    to verify challenging examples. eg. complex.py.anormalnt
    
+ Related files:

  + The concolic RAD:
    * pycesk3-smt-summarize.rkt
    * pycesk3-smt.rkt
    * utils_cesk3_smt.rkt
    * folder sv_tests-conc-res includes the sample output files (z3 files and verified results)
    
  + The entangled RAD:
    src:  in the smt-list-bound folder
    sample output files: smt-list-bound/sv-tests-part-res
    
  + The python test source file:
    sv_test/test_pyfiles
    sv_test/*.* IR files generated from the pipelines of the compiler.

  + Other framework files can be ignored.

  
+ How to run:

  * Environments:
    * Racket 5.2.1
    * `z3.rkt` requires Z3 4.0, which you can download for your platform from [the
      Microsoft Research
      site](http://research.microsoft.com/en-us/um/redmond/projects/z3/download.html).
      We work on Windows, Mac and Linux. You need to copy or create a symlink to `z3.dll`,
      `libz3.so` or `libz3.dylib` in this directory.
      
 * For simplicity, you don't have to generate IR files from the test python files.
   They have been generated for you.

   You can go into pyana folder:
   make pycesk - to compile the concolic RAD
   make verify-conc-tests - to run the test files

   go to smt-list-bound folder:
   make pycesk - compile the entangled RAD
   make verify-part-tests - to run the test files.

 * If you want to test your own python source files:

   go to pyana directory:

   make compile - to compile all including lexer, parser, translator, desugar,
     	  anormalizer and the relational analysis.
   sh ./Make1Py.sh your/python/file 0 4 - to generate the anormalized IR
   ./pycesk3-smt-summarize-rkt the/generated/anormalized-file

   Or

   ./pycesk3-summarize-smt /the/generated/anormalized-file


   
For any question to run, please contact liangsy@cs.utah.edu
