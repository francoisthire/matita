module reduce_cbv.

copy (app M N) (app M2 N2) :- copy M M2, copy N N2.
copy (lam F) (lam F2) :- pi x\ copy x x => copy (F x) (F2 x).

cbv (lam F) (lam F2) :- pi x\ cbv x x => copy x x => cbv (F x) (F2 x).
cbv (app M N) R2 :-
 cbv N N2,
 cbv M M2,
 beta M2 N2 R2.

beta (lam F) T R2 :- !,
 (pi x\ copy x T => copy (F x) R),
 cbv R R2.
beta H A (app H A).

main :-
 (ZERO = lam s\ lam z\ z),
 (SUCC = lam n\ lam s\ lam z\ app s (app (app n s) z)),
 cbv (app SUCC ZERO) ONE,
 (PLUS = lam n\ lam m\ lam s\ lam z\ app (app n s) (app (app m s) z)),
 (MULT = lam n\ lam m\ lam s\ app n (app m s)),
 cbv (app SUCC (app SUCC ZERO)) TWO,
 cbv (app (app PLUS (app (app PLUS TWO) TWO)) TWO) SIX,
 cbv (app (app MULT SIX) TWO) TWELVE,
 (EXP = lam n\ lam m\ app n m),
 cbv (app (app PLUS TWO) ONE) THREE,
 cbv (app (app EXP TWO) THREE) NINE,
 cbv (app (app MULT TWO) TWO) FOUR,
 cbv (app (app PLUS THREE) TWO) FIVE,
 cbv (app (app PLUS FOUR) TWO) SIX,
 cbv (app (app EXP FIVE) FIVE) RES,
 cbv (app (app EXP FIVE) FIVE) RES,
 cbv (app (app EXP FIVE) FIVE) RES,
 cbv (app (app EXP FIVE) FIVE) RES,
 cbv (app (app EXP FIVE) FIVE) RES,
 cbv (app (app EXP FIVE) FIVE) RES.
