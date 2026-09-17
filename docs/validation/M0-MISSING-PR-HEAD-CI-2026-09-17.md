# Missing PR-head CI batch — 2026-09-17

All36 finite workflow_dispatch runs for existing PR3–38 branch heads completed success. Every observed headSha equals the dispatch expectedHead. No source or branch changes, review requests, merge/rebase/stack registration or publication were performed.

These are branch-head workflow results; PR3 statusCheckRollup was observed empty despite its successful manual run. Do not represent these as attached PR checks or current unpublished-source validation. Base changes/rebases require fresh exact-pair correctness assessment and appropriate CI.

Remaining merge preparation: ten drafts43/51–59; nonlinear history layers31/32/33/35/51/53/57/59; PR2 finite-page-box extent finding still exists at PR59 and its tested fix is unpublished. Green CI alone does not resolve these. PR60 is a conflicting sibling. No native stack conversion performed.

## Exact observed results

| PR | Head SHA | Successful run |
|---|---|---|
| #3 | `5e8b19692a2a2a67a67529794ae31b8d1bea429a` | [run 35280386109](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35280386109) |
| #4 | `610c0fef36ec5c2a824ee6a4ad5f4b6dddd3d2a1` | [run 35280388900](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35280388900) |
| #5 | `14456641a851a873f363c0c6b5a148ee7f8cf1e2` | [run 35280390943](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35280390943) |
| #6 | `7e6c9a4a6c3e4957a91d10db22cf705ca2285e30` | [run 35280393357](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35280393357) |
| #7 | `1b4cc0a3794755ed0ba02ea3ed057a39cfed51ec` | [run 35280395595](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35280395595) |
| #8 | `5ad4ceb685f09699af318355301fc3bab5aca3e1` | [run 35280397935](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35280397935) |
| #9 | `7a2d3fcc19d7ce0adaea3b756b3e8e6d89c3df3d` | [run 35280400089](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35280400089) |
| #10 | `c3eab79c89961cdca1ecb2b532c76c8a4b3b9fc7` | [run 35280402502](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35280402502) |
| #11 | `4b39352c8383c45b98eb15a2d431df853a3b54db` | [run 35280404424](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35280404424) |
| #12 | `2f8260bff10d7d882dfe97eafb0daf4fb0e1ac41` | [run 35280406456](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35280406456) |
| #13 | `b9b5240b0ddc11dfa89fd2086c2034a35003fdf5` | [run 35280408420](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35280408420) |
| #14 | `f30912167f8a0bfe1d690b19d8a7fa66ca46712f` | [run 35280411067](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35280411067) |
| #15 | `0fef58f75d5336514cf1680956bb8a49e8af6535` | [run 35280413852](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35280413852) |
| #16 | `9957739cb29607942c87bfbf7da3fb8987c760b5` | [run 35280416009](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35280416009) |
| #17 | `f2614d548a031b61ab822c5e077c5f04e7cb7fb0` | [run 35280418394](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35280418394) |
| #18 | `3b0fe086806a51f9de383ed620ecc547056b4640` | [run 35280420627](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35280420627) |
| #19 | `0764ca113d7a4678acc7927da3701bb6da0f8167` | [run 35280423030](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35280423030) |
| #20 | `14f37252b007bf5eef3482119db9497e51c97e42` | [run 35280425448](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35280425448) |
| #21 | `85f3a85f073a837705d7aa545ca095fced686904` | [run 35280427737](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35280427737) |
| #22 | `a4b236dab3925e71dc26d91a37e24b2fdd90c196` | [run 35280430114](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35280430114) |
| #23 | `952b476cdb93eec7379a53cdfd9f2a65f205de5a` | [run 35280432068](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35280432068) |
| #24 | `bde2f5fe88530d1d58ab3ca0a3324c8148de00b8` | [run 35280433987](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35280433987) |
| #25 | `8890a199c9b2864febb379fec51a92fb4dcc2901` | [run 35280435993](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35280435993) |
| #26 | `15a2357b314f432734962d8c78af97690cb6c497` | [run 35280438212](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35280438212) |
| #27 | `a38d7eff0ecb5321a747f9bcd3b681f33aa92872` | [run 35280440773](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35280440773) |
| #28 | `b3aca1110721731a2ddefa9d41aee499b3cabafc` | [run 35280443212](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35280443212) |
| #29 | `6f5217f8b3e3634b763b1964d5483a22f43e1645` | [run 35280445439](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35280445439) |
| #30 | `efc03623076c8ca6c903a0d57e8f8d2e6851fb52` | [run 35280447870](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35280447870) |
| #31 | `e303269726491f0b86fa2d878bd79e81478ed01e` | [run 35280450255](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35280450255) |
| #32 | `df611c7f38ac40687c22c6cd2e91b1827e43749d` | [run 35280452567](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35280452567) |
| #33 | `c6af24268bbdc8a4b01ba0e161da95834d1f6e63` | [run 35280454607](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35280454607) |
| #34 | `0f9673252a722ac65f442c538aaeb3aebe0cc58e` | [run 35280456673](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35280456673) |
| #35 | `953e4a080d6228e805edf1476a08533436d6653f` | [run 35280459007](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35280459007) |
| #36 | `e4dcde341db551343426af19578bf60aeb0666a2` | [run 35280461291](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35280461291) |
| #37 | `312a3352ac104955040f92d403275bf946f4a4de` | [run 35280463774](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35280463774) |
| #38 | `616896072433b5185f5f1f8dd3885c1400607ba9` | [run 35280466213](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35280466213) |
