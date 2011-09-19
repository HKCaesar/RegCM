!::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
!
!    This file is part of ICTP RegCM.
!
!    ICTP RegCM is free software: you can redistribute it and/or modify
!    it under the terms of the GNU General Public License as published by
!    the Free Software Foundation, either version 3 of the License, or
!    (at your option) any later version.
!
!    ICTP RegCM is distributed in the hope that it will be useful,
!    but WITHOUT ANY WARRANTY; without even the implied warranty of
!    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
!    GNU General Public License for more details.
!
!    You should have received a copy of the GNU General Public License
!    along with ICTP RegCM.  If not, see <http://www.gnu.org/licenses/>.
!
!::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

module mod_cbmz_solve1
!
  use m_realkinds
  use mod_cbmz_chemmech
  use mod_cbmz_chemvars
  use mod_cbmz_chemlocal

  private

  public :: quadchem
!
  contains
!
!  chemsolve.f (quadchem.f)   June, 2009
!   chemsolve_609.f June, 2009
!
!  Programs to solve for species concentrations
!   using the RADICAL BALANCE-BACK EULER solution for photochemistry.
!
!  Full notes on development are in the FILE chemsolnotes
!
!   CURRENT UPDATES:
!
!    June 2009: SETGEOM for NOX CONVERGENCE.  (OPTION).
!    June 2009: Separate Hx sums for Hx with and without RO2 (2009 CHANG
!    changed also in cheminit1.f, chemmech.EXT, chemlocal.EXT )
!    changed LSELF flag - depends on rate but not during 1st iter
!
!    NOTE:  2008 version:  chemmech.EXT before chemvars.EXT.
!
!  CURRENT ISSUES:
!    IFORT compiler.
!    slow and  uncertain aqueous/Br, Cl, NOx solution.  (see PROBLEMS)
!    NOX CONVERGENCE OPTION: geom avg or SETGEOM
!      (currently SETGEOM - experimental.)
!
!  Compile for box model:
!   boxmain.f boxpro.f chemmainbox.f cheminit.f chemrates.f quadchem.f
!    (aquasolve.f) linslv.f jval2.f
!  Include:  chemvars.EXT, chemmech.EXT, chemlocal.EXT, boxvars.EXT
!
!  Input files:
!     REACTION.DAT (REACTION7_GMI_AQHG06)  :  mechanism
!     TUVGRID2                             :  hv data, see jval2.f
!     fort.87  (fort.87hg_gmi_rpa)         :  concentrations+emissions
!     fort.41                              :  Run setup
!       (also REACTION7_GMI_LKS06hv with fort.87gmifull-global - update)
!           (fort.87gmi-global - GMI w/telomers. No REACTION7 yet.)
!
!     Tests:  fort.43test407.
!       Includes 12-hr expo decay (2a vs 2b), + full chem P-L cases.
!     Time test:  See quadchv7.f for comparison between versions.
!
!     Future option: nonsteady  state aqueous
!     Future option: exponential decay  solution (done, currently availa
!     Long-term option: integrate with aerosol solution
!
!  Subroutines:
!     quadchem:  driver program for radical balance solver
!     chemsolve: solution for individual species, pairs or groups.
!     brreac:    calculates rate for specified reaction
!     brpro:  calculates rate, assigns production and loss for reaction
!     excorr:  corrects OH production sums for 'exchange' reactions
!     noxsolve:  solution for NO, NO2 and O3
!     ohsolve:   solution for OH and HO2 (also modifies CO3-)
!     setgeom:   Sets geometric averaging based on past iterations
!     presolve:  Preliminary approximate solution for O3, NOx, OH, NO3.
!     prelump:   Sets initial concentrations for 'lumped' species
!                  and sets initial aqueous=0.
!    midlump:    Re-sets 'prior' partitioning for lumped species
!                  based on interim chemical production rates.
!    postlump:   Sums lumped species and aqueous species into gas master
!                  after calculation is complete.
!    ohwrite:    Writes details of odd hydrogen balance.
!
!
!  Time tests of versions - see quadchv7.f and fort.43test1106,407
!
!  Program  written by Sanford Sillman
!  ---------------------------------------------------------
!  Program history:
!    12/06 Initial program by Sandy Sillman based on boxchemv7.f
!    6/09 Modifications: expo decay, separate Hx w/ and w/o RO2
!  ---------------------------------------------------------
!
! Notes:
! Features of this solution:
!   This part of the program uses sums of gas and aqueous species
!     that are linked through Henry's law and aqueous equilibria.
!   It solves for them as a single "species",
!     based on chemical production/loss,
!     and leaving the gas/aq partitioning intact.
!   A separate program (aquasolve) solves for gas/aqueous partitioning.
!     (the chemistry  and gas-aqueous are solved in iterative sequence)
!
!   This solver uses the 'radical balance' approach.
!    It solves for OH and HO2 based on production/loss of radicals
!    Each radical source/sink is also assigned a sensitivity to OH.
!    OH is solved from a linear interpolation:
!      radical sources-sinks = A + B*OH
!      (This is a fragment of the full back-Euler equation
!         with a sparse matrix)
!
!   Other species are solved individually
!                                 in reactant-to-product sequence.
!
!      (species with mutual interactions are solved individually
!        if they interact slowly - e.g. RO2 and ROOH)
!
!   This version includes solutions for
!    (1) interacting pairs of species (e.g. MCO3-PAN)
!    (2) "chains" of paired species (e.g. Hg0<->HgOH<->HgCl etc)
!         (format:  A<->B, A<->C, C<->C2, etc.)
!    (3) full back-Euler sub-solution for 3 or more interacting species.
!
!   Other features:
!
!    OH-HO2 solution based on Hx sources/sinks WITH or W/O RO2
!      depending on rate of RO2+NO reaction vs timestep (sec-1).
!      If RO2+NO is slow (night), OH-HO2 decoupled from RO2.
!
!    Aqueous CO3- is included as odd-H
!
!    Geometric averaging of present and prior solutions for OH:
!      the geom. averaging parameter is set based on iterative history.
!      (range 0.1-1.0 - it decreases when the iteration oscillates).
!      OPTION:  set minimum value for geometric parameter (0.1 or 0.5)
!              (0.1 for slow, sure convergence.  Max is always 1.)
!
!  PLANNED FUTURE IMPROVEMENTS (June 2009)
!   Vectorized version
!   (CBM-Z version)
!   Test condesned version, add condensed aqueous
!   (Write paper on numerics following EPA 2007 presentation)
!   (write condensed version)
!   Eventually add integrated solution for aerosols
!
!  --------CORRECTED AND ONGOING PROBLEMS-----------------------
!  FUTURE ADD:  Identified below by 'FUTURE ADD'.
!     Exponential decay solution option DONE
!     lself flag for MCO3, AHO2 - not nec. because self reaction is smal
!       but is critical for H2O2, SO5l - add a bypass for better converg
!       MUST BE SKIPPED for NO3, N2O5
!       ADD SKIP   WHEN SMALL.    - rself   - (2009 dont skip for 1st it
!       DONE- NEED TO TEST
!     Non-steady state gas/aqueous partitioning
!     Categories for aqueous/soluble aerosol species
!           (for non-steady-state gas/aq partitioning)
!     NOXSOLVE - why does MULTISOLVE not work;  add O1D;  setgeom for no
!     Vectorize the remaining parts of the program:  hv rates.
!
!     Modify to skip aqueous reactions if LWC=0:
!      assign reactants to direct species, not gas pointer
!      and in chem, do reactions only when species is called
!           - if LWC=0 skip aqueous
!
!  --------CORRECTED AND ONGOING PROBLEMS-----------------------
!
!  ONGOING ISSUES:  (June 2009)
!    IFORT compiler fails unless -C flag is used (xeonsrv)
!    Check convergence criteria - is recent correction OK?
!    NOX CONVERGENCE OPTION: geom avg or SETGEOM?
!      (currently SETGEOM - experimental.)

!    Br-Cl aqueous reactions may be difficult to include, may need multi
!     test cases to see.
!
!   Br nighttime nonconvergence/oscillation in AQHG06,
!    better if HBRG separate in cascade, then BRG-BR2G, rather than trip
!    -> DEBUG TRIPLE IN CASCADE (HBRG-BRG-BR2G)
!    -> NO2-HNO3 OSCILLATION, try setgeom for NOx;  NO.
!     (fort.87rb_hg_rpai w/ aq .3e-6)
!
!   ClOH- has always been difficult due to back-forth reaction with OH.
!     This can cause oscillating solution.
!     Solved using multisolve + geometric averaging for OH.
!
!  STANDARD TESTS:
!  Hour 2 and 12; condensed w/ steady state; AQHG06 w/ acqua=0.3e-6, 298
!      (REACTION.COHC3 w/ fort.87cohc3, fort.87 cohc_u)
!      (REACTION7_GMI_AQHG06 w/ fort.87rb_hg_rpai -> NOTE HBRG CASCADE O
!
!   MOST RECENT CORRECTIONS:
!
!    NOX CONVERGENCE OPTION: SETGEOM instead of geom avg.
!
!      CONVERGENCE OPTION (June 2009): geom avg, lself and 1st few itera
!              (1, 2 or 3 iters, and skip if 1st iter and steady state)
!        NOT USED.
!       (This may help with aqueous test case:
!                               AQHG06 fort.87rb_hg_rpai ,aq=0.3e-6)
!         but hurts slightly with condensed steady state case just below
!
!      BR cascade: HBRG, then BRG-BR2G, rather than triple HBRG-BRG-BR2G
!           (need to investigate further, June 2009)
!
!      Hx WITH OR WITHOUT RO2 (June 2009):
!      Hx sums (oddhsum, etc.) are done for Hx with or without RO2
!      Final solution is weighted based on rate of RO2+NO vs 1/timestep
!      Corrects for night/low NO: OH-HO2 and RO2 become dissassociated.
!      -> Corrects for nighttime  case w/ steady state OH HO2 RO2
!         (REACTION.COHC3 and fort.87cohc3 rural)
!
!     SENHCAT OH ADJUSTMENT (June 2009):
!      senhcat based on rlHO2 vs rpH2O2 - assumes rpH2O2 = HO2+HO2
!      error can occur when there are other sources (TERP+O3)
!      correction: insure rpH2O2<rlHO2
!
!     CONVERGENCE CRITERIA corrected (June 2009)
!
!     PRIOR HX SUM changed to not double-count lumped species (June 2009
!
!     LSELF: flag set for 1st 2 iterations, regardless of reaction rates
!      after 2nd iteration, flag set only if significant self-reaction (
!
!   LSELF  408 version. lself correction  (rself) added.
!     lself flag false unless significant self-reaction.
!     when true, use geometric averaging. (2009: skip for 1st iter)
!
!   NOTE:  408 OPTION, SKIP PAIR ADJUSTMENT if zero production.
!
!      PRODUCT=REACTANT PAIR ADJUSTMENT in brpro/stoicx (2008):
!        subtract from rp, rl if product=reactant,
!        subtract from rppair, rlpair if prod, react in same pair group,
!          but (2008 correction) not if product=reactant.
!
!      PAIR ADJUSTMENT OPTION (minor - in chemsolve):
!      SKIP PAIR ADJUSTMENT in case with zero rpro.  (TEST 2008 OPTION)
!          else small num error DCO3-DPAN-aeDPAN if aero rate=0;
!         since pair structure A-C, C-C2 solves C-C2 first,
!         and solves A-C with fixed C-C2 ratio. trivial error if C2=0.
!         CORRECTED with skip ('TEST 2008').  see dlolcese08/fort.43pair
!
!     * SELF-REACTION CORRECTION: lself-rself in chemsolve (important!)
!       geom avg solution only if significant self-reaction.
!         to prevent error DCO3-DPAN-aeDPAN (lolcese) and NO3-N2O5.
!       Tested for SO5G-HSOG error (aq). (REACTION7_AQHG06, fort.87rb_hg
!
!     NO3-N2O5 no lself: geom avg causes nonconvergence w/NOx at high NO
!             hardwired lself=F, to avoid geom avg.
!             later lself/rself error also fixes this.
!     MULTISOLVE option for aqueous Cl-, Br-
!     Conservation-of-mass adjustment for pair groups.
!     H2O2 still has special geometric solution.
!     CO3 is linked to the radical solution, adjusted based on Hx.
!
!   Corrected problems:
!     OH+Cl=>ClOH caused nonconvergence
!       - fixed with multisolve and geometric averaging.
!     Hg oscillated with aqueous Hg=0:
!       - the problem was a too-high zero protect (if xr<1e-20).
!     EXCORR can cause errors if it links two NON-PAIRED species.
!       - the excorr species must always be solved as pairs.
!
!  Full notes (including TIME TESTS and IMPROVEMENTS)
!     are in quadchv7.f -> chemsolnotes
!
! =============
! --------------------END PROGRAM INFORMATION---------------------
!
! This is the driver program
!   for the radical-balance back-Euler solution for photochemistry.
!
! It calls a preliminary partitioning (prelump),
! Establishes a preliminary solution (presolve)
! And then sets up a standard iteration.
!
! The iteration includes:
!    aquasolve: program to solve for gas-aquoues partitioning
!    chemsolve:solution for individual species or for species pairs
!      called in reactant-to-product order.
!    ohsolve:  radical balance solution for OH and HO2.
!
! Input and output to the program operate through the common blocks
!  (chemvars.EXT and chemmech.EXT)
!
! Input and output are processed by chemmain (file chemmainbox)
!
! Called by:    boxmain.  (This is called for main solution)
! Calls to:
!           chemrates   - set rate constants
!           hvrates     - set hv rate constants
!           prelump     - initial partition of lumped and gs-aqueous sp.
!           presolve    - initial solution for OH
!           midlump     - interim partition of lumped species.
!           aquasolve   - solution for gas-aqueous partitioning
!           chemsolve   - solution for individual species and groups
!           ohsolve     - solution for OH/HO2
!           postlump    - sum lumped species into lump sum,
!                          and aqueous into gas-master.
!
! ---
!
!  Program  written by Sanford Sillman
!  ---------------------------------------------------------
!  Program history:
!    12/06 Initial program by Sandy Sillman based on boxchemv7.f
!  ---------------------------------------------------------
! ---------------------------------------------------------------
!
    subroutine quadchem
!
      implicit none
!
      ! Species list passed to chemsolve
      integer ncsol(c_cdim)
!
      kk=1
!
! PRELIMINARY CALLS:  BEFORE SOLUTION
!   Note, must also call the initial read + process at the start.
!     chemread, hvread and cheminit
!
! OPTION:  CALL HERE TO SET REACTION RATE AND HV CONSTANTS.
!   (can be here or in chemmain1.f)
!
!  SET REACTION RATE CONSTANTS
!     call chemrates
!
! SET PHOTOLYSIS RATE CONSTANTS
!     call hvrates
!
! (end OPTION)

!
! SET H2O CONCENTRATION IN CHEMISTRY ARRAY FROM INPUT VARIABLE
      if (c_nh2o > 0 ) then
       xc(kk,c_nh2o) = c_h2ogas(kk)
      end if
!
! PRELUMP:  SETS 'PRIOR' CONCENTRATIONS (XXO) AND LUMPED SPECIES
!
      call prelump

! PRELIMINARY SOLUTION FOR OH, HO2, O3, NOx.  :
! Solution uses the following reactions:
!       #1:  NO2+hv->NO+O3          #2: NO+O3->NO2
!       #9:  O3+hv->2OH             #12: NO2+OH->HNO3
!       #16: OH+CO->HO2             #17: OH+O3->HO2
!       #18: HO2+NO->OH+NO2         #22: HO2+HO2->H2O2
!       #46: OH+CH4->HO2
!
      call presolve

! ---------------------------------------------------------------
!  BEGIN ITERATIVE RUNS
! ---------------------------------------------------------------
      runiter: &
      do c_iter = 1 , c_numitr
        if ( c_kkw > 0 ) then
          write(c_out,1901) c_iter
          write(c_out,1902)
        end if

! RE-SET PARTITIONING OF LUMPED SPECIES BASED ON CHEM. PRODUCTION.
        if ( c_iter >= 2 ) call midlump

! SET RATES FOR PARAMETERIZED RO2-RO2 REACTIONS, IF ANY
        if ( c_nnrro2 > 0 ) call setro2

! CALL AQEOUS CHEMISTRY SOLVER FROM WITHIN ITERATION
!          (NON VECTOR VERSION - call only if LWC nonzero)
!       call aquasolve
        if ( c_h2oliq(1) >= 1.0D-20) call aquasolve

! SET SENHCAT FOR FIRST ITERATION. (sensitivity to change in OH).
! INITIAL SENHCAT = 1 FOR ODD HYDROGEN; 0 FOR OTHER SPECIES

        if ( c_iter == 1 ) then
          do ii = 1 , 30
            is = 0
            if ( (ii == 8 .or. ii == 9 .or. ii == 10) .or. ii == 3) is = 1
            senhcat(kk,ii) = dble(is)
          end do
        end if

!  WRITE SENHCAT
        if ( c_kkw > 0 ) then
          write(c_out,1611) (senhcat(c_kkw,ii),ii=1,20), &
                            (senhcat(c_kkw,ii),ii=31,40)
        end if

! ZERO ACCUMULATED SUMS AT START OF EACH CASCADE LOOP:
!   oddhsum = summed net source/sink for odd hydrogen radicals
!               1=w/RO2 2=just OH, HO2, CO3
!   oddhdel = sum of each net source/sink of oddh
!                multiplied by sensitivity to OH concentration.
!   oddhsrc = summed source only
!   oddhloh = summed loss of OH
!   oddhlho2 = summed loss of HO2 (removal)
!   sourcnx = summed NOx source
!   sinknx = summed NOx sink
!
!   rrp, rrl = running sum of production, loss of each species
!              not set to zero here - zero when spec. is solved.
!
!   c_rr  reaction rates.
!
! ALSO,  PRESERVE PRIOR CONCENTRATION HERE
! xclastq =PRIOR BUT AFTER AQUASOL)

        do ic = 1 , c_nchem2
          xclastq(kk,ic) = xc(kk,ic)
        end do

        do i = 1 , 2
          oddhsum(kk,i) = d_zero
          oddhsrc(kk,i) = d_zero
          oddhdel(kk,i) = d_zero
          oddhloh(kk,i) = d_zero
          oddhlho2(kk,i) = d_zero
        end do
        sourcnx(kk) = d_zero
        sinknx(kk) = d_zero

! -------------------------------------------
! CASCADE SOLUTION for individual species or species groups:
!  SPECIES CALL IS SET BY ORDERED ARRAY c_cascade ->ncsol
! -------------------------------------------
!
!
! REGULAR DEBUG WRITE - OPTION
!        if(c_kkw.gt.0.and.c_iter.eq.1) write(c_out,1663)
! c        if(c_kkw.gt.0              ) write(c_out,1663)
! 1663     format(/,' CASCADE:  CHEMICAL INDICES:')


! LOOP TO CALL SPECIES SOLUTION
        do i = 1 , c_nchem2
          if ( c_cascade(i,1) == 0) exit
          do ic = 1 , nsdim
            ncsol(ic) = c_cascade(i,ic)
          end do

! REGULAR DEBUG WRITE - OPTION
!        if(c_kkw.gt.0.and.c_iter.eq.1)
!    *        write(c_out,*) (ncsol(ic),ic=1,3)

          call chemsolve(ncsol)
        end do ! END CASCADE LOOP
! -------------------------------------------
!
! -----------------------------
! SPECIAL TREATMENT FOR NO3-N2O5 - HNO3
! -----------------------------
!
! NO3-N2O5 is solved normally, as paired species
! HNO3 is solved first, then NO3-N2O5.
!  (pair declaration is hard-wired in chemread)
!
! IT IS 'SPECIAL' ONLY BECAUSE IT REQUIRES A SPECIAL CATEGORY
! NO3 REACTS WITH MOST SPECIES; SO SPECIES MUST NOT BE ASSIGNED
! TO NO3.
!
        ic1 = c_nno3
        ic2 = c_nn2o5
        ic3 = c_nhno3
!
! ERROR? comment out?
!       call chemsolve(ncsol)

        do ic = 2 , nsdim
          ncsol(ic) = 0
        end do
        ncsol(1) = ic3
        call chemsolve(ncsol)
        ncsol(1) = ic1
        call chemsolve(ncsol)

! -------------------------------------------
! SPECIAL TREATMENT FOR NOX-OX AND ODD HYDROGEN FAMILIES
! -------------------------------------------
! O3-NOx SPECIAL SOLUTION:
! SIMULTANEOUS FOR THREE SPECIES, USING OX AND NOX RELATIONSHIPS.
! THIS IS INCLUDED IN SUBROUTINE 'NOXSOLVE', INVOKED BY CHEMSOLVE.
!
! TO USE, INVOKE CHEMSOLVE(IC1,IC2,IC3) IN PRECISE ORDER: O3, NO2, NO.
! IDENTIFIED BY SPECIAL SPECIES INDEX
! THE KEY REACTIONS O3+NO->NO2, NO2+hv->NO+O3 ARE SUMMED IN CPRO.
!
! TEMPORARY DEBUG  WRITE
!      if(c_kkw.gt.0) write(c_out,221) xc(c_kkw,1),xc(c_kkw,2),xc(c_kkw,
! 221    format('BEFORE-NOXSOLVE: O3 NO2 NO=',3(1pe10.3))

        do ic = 2 , nsdim
          ncsol(ic) = 0
        end do

        ncsol(1) = c_no3
        ncsol(2) = c_nno2
        ncsol(3) = c_nno

        call chemsolve(ncsol)

! ---------------------
! ODD HYDROGEN SOLUTION:
! ---------------------
!   CALL SUBROUTINE OHSOLVE(OH,HO2,H2O2) TO SOLVE FOR OH, HO2.
!   SPECIES IDENTIFIED BY SPECIAL  INDEX

        call ohsolve(c_noh, c_nho2, c_nh2o2)

!  (computer alternative)
!     ic9=c_noh
!     ic10=c_nho2
!     ic11=c_nh2o2
!     call ohsolve(ic9,ic10,ic11)

! --------------------------------------
! END OF ITERATION.  WRITE, TEST AND EXIT.
! --------------------------------------

! -------------------------------------------------------
!  SUMMARY ITERATIVE WRITE:  THIS SECTION (ALONG WITH OHWRITE)
!  CAN BE COPIED AND USED OUTSIDE QUADCHEM. (see CHEMWRIT)
! -------------------------------------------------------
! IF LPRT OPTION (KKW>0) WRITE FULL SUMMARY FOR ITERATION.
! (WRITES FOR NOX AND HX ARE IN NOXSOLVE AND OHSOLVE)
!
! QUADCHEM ITERATIVE WRITE:
! NOTE:  WRITE GAS+AQUEOUS SUM HERE,  AND LIST OF REACTIONS.
!        GAS-AQUEOUS PARTITIONING ITER SUMMARY is in AQUASOLVE.

        if ( c_kkw > 0 ) then
          write(c_out,1801) c_iter, c_kkw
          write(c_out,1804) c_IDATE, c_hour,  c_lat(1), c_lon(1),c_temp(1)
          write(c_out,1805) (c_jparam(i),i=1,13),c_jparam(20)
          write(c_out,1802)

! OPTION:  ORIGINAL WRITE (all species)
!       do 1810 j=1,c_nchem2
!        write(c_out,1803) j, c_tchem(j),xc(c_kkw,j),  c_xcin(c_kkw,j),
!    *       c_rl(c_kkw,j), c_rp(c_kkw,j)
! 1810    continue

! OPTION:  WRITE GAS-AQUEOUS SUMS
!   MAKE XR,  RP, RL=sum ; write gas-masters only

          do j = 1 , c_nchem2
            if ( c_npequil(j) == j ) then
              xrr(c_kkw,1) = d_zero
              rpro(c_kkw,1) = d_zero
              rloss(c_kkw,1) = d_zero
              do neq = 1 , (c_nequil(j)+1)
                ic = j
                if ( neq > 1 ) ic = c_ncequil(j,(neq-1))
                alpha(c_kkw) = d_one
                if ( neq > 1 ) alpha(1)= c_h2oliq(1)*avogadrl
                rloss(c_kkw,1) = rloss(c_kkw,1)+c_rl(c_kkw,ic)
                rpro(c_kkw,1)  = rpro(c_kkw,1) +c_rp(c_kkw,ic)
                xrr(c_kkw,1)   = xrr(c_kkw,1)  +xc(c_kkw,ic)*alpha(c_kkw)
              end do
              beta(1)   = xrr(c_kkw,1) - c_xcin(c_kkw,j)
              cgamma(1) = rpro(c_kkw,1) - rloss(c_kkw,1)
! TEMPORARY CHANGE (45  )
              if (.not. c_lsts(ic) ) cgamma(1) = cgamma(1)-beta(1)
              write(c_out,1803) j, c_tchem(j), xrr(c_kkw,1), &
                 c_xcin(c_kkw,j), xcfinr(c_kkw,j), rloss(c_kkw,1), &
                 rpro(c_kkw,1), beta(1), cgamma(1)
            end if
          end do

! OPTION - INCLUDE REACTIONS
          write(c_out,1806) c_iter,c_kkw
          do nr = 1 , c_nreac
            write(c_out,1807) nr, (c_treac(j,nr),j=1,5), &
               c_rr(c_kkw ,nr), ratek(c_kkw ,nr)
          end do
        end if
! END SUMMARY WRITE
! --------------------------------------------------------

! IF KMAX=1, USE CONTROLS TO TEST FOR CONVERGENCE AND EXIT.
! IF VECTORIZED (KMAX>1), NO CONTROLLED EXIT
!   NOTE NIGHTTIME ADDED EXIT ABOVE: XOHTEST,FOHTEST*0.001.

        if ( c_kkw > 0 ) write(c_out,1701) c_iter,c_ohtest,c_notest

        if ( c_kmax == 1 ) then
          if ( ratek(1,1) >= 1.00D-04 .and. c_ohtest < xfohtesti ) then
            c_ohtest = xfohtest
          end if
          if ( c_iter > 3 .and. (c_ohtest < c_converge .and. &
               c_notest > c_converge)) exit runiter

! ADDED EXIT: IF NOX CONVERGES AND OH IS LOW:
! REPLACED BY LOWERING XOHTEST, FOHTEST.
!  NOTE, THIS REQUIRES HARD-WIRED RATEK(1), XR(OH).
!          if(c_iter.gt.3.and.ratek(1,  1).lt.0.001.and.
!    *       (xc( 1 , 9).lt.0.100E+06 .and.c_notest.lt.c_converge))
!    *          go to 1710

        end if

      end do runiter
!
! -----------------------
! END ITERATIVE LOOP
! -----------------------

! POSTLUMP:  SUM LUMPED SPECIES INTO LUMP-SUM AND CONVERT CONCENTRATIONS
! TO LUMP-PARTITION FRACTIONS.  (Also sum Aq-Equil species?)

      call postlump

 1611 format(/,'TEST SENHCAT 1-20,31-40:',/,(10f6.3))
 1701 format(/' TEST FOR OH,NO CONVERGENCE =',i3,2(1pe10.3))
 1801 format(//,' SUMMARY WRITE:  ITER =',i3, '    VECTOR KKW=',i3)
 1802 format(/,' #  IC     XCOUT     XCIN  XCF/AV       RL',       &
                    '        RP        dXC      dR')
 1803 format(i4,a8,2(1pe10.3),0pf7.3,1x,(4(1pe10.3)))
 1804 format('IDATE xhour lat lon temp=',i8,4f8.2)
 1805 format('JPARAMS: zenith altmid dobson so2 no2 aaerx aerssa', &
        ' albedo',/,'cld-below cld-above claltB claltA temp date', &
         /,(8f10.3))
 1806 format(//,' REACTION RATES:  ITER =',i3, '    VECTOR KKW=',i3)
 1807 format(i4,2x,a8,'+',a8,'=>',a8,'+',a8,'+',a8,2(1pe10.3))
 1901 format(//,70('-'),/,'BEGIN ITERATION =',i3)
 1902 format(70('-'),/)
!
    end subroutine quadchem
!
! -----------------------------------------------------------------
!
! ----------------------------------------------------
! SOLVER SUBROUTINES - SOLVE FOR INDIVIDUAL SPECIES CONCENTRATIONS
! ----------------------------------------------------
!
!     FUTURE DO:  back-Euler solution for multi-species
!
! This is the main solver for individual species concentrations.
! It includes:
! (1) A solution for an individual species -
!      (regarded as a sum of gas + aqueous linked through equilibria)
!
! (2a) A solution for a pair of rapidly interacting species
!
! (2b) A solution for a 'chain' of linked pairs
!                                       (A<->B, A<->C1, C1<->C2, etc.)
!
! (3) A reverse-Euler solution for a group of 3+  interacting species.
!      ('MULTISOLVE')
!
! (4) Call to special solution for O3-NO2-NO ('NOXSOLVE')
!
! It also establishes rates for reactions associated with the species;
! And calculates summed production, loss of reaction products,
!  and odd hydrogen radical sums.
!
!  FOR A SINGLE SPECIES OR PAIR, MAKE IC2<=0.
!
! THE SOLUTION SEQUENCE:
!  (a) Calculate losses/rates of reactions tht affect the species
!      (including linked gas+aqueous equilibrium species)
!  (b) Solve for species concentrations
!        with separate solutions for:
!         SINGLE SPECIES
!         PAIR AND PAIR CHAIN
!         NOXSOLVE
!         MULTISOLVE
!  (c) Add production of product species and odd-h radicals
!       to the production sums.
!
!  Input: Prior species concentrations, reactions and rate constants.
!  Output:  Updated species concentrations (xc).
!
! Called by:  quadchem.
! Calls to:
!     brpro - sums production and loss from reaction
!     brreac - calculates reaction rates.
!     setgeom - establish geometric mean parameter for iteration
!     noxsolve - solution for O3-NO-NO2
!     LINSLV - matrix iteration for MULTISOLVE solution.
!
! ---------------------------------------------
! History:
!  12/06 Written by Sandy Sillman from boxchemv7.f
!
! -------------------------------------------------------------------
! ----------------------------------------------------------------
!
!  PREVIOUS:  FOR TWO SPECIES THE 'EXCHANGE' SPECIES MUST COME FIRST.
!  NO LONGER.  EXCHANGE IS NOT DEPENDENT ON ORDER-OF-SPECIES.
!  (ONLY NOXSOLVE USES RPRO, RLOSS, CPRO FROM CHEMSOLVE
!    IN A SPECIFIC ORDER.  EXCORR IS NOT CALLED FOR NOX.)
! ----------------------------------------------------------------
!
!
    subroutine chemsolve(ncsol)
!
      implicit none
      ! Species list passed to chemsolve
      integer :: ncsol(c_cdim)
      ! Flag for exponential decay solution
      logical :: llexpo(c_kvec)
      ! Flag for completion of expo deca
      logical :: doneexpo(c_kvec)
      ! For back-Euler solution
      real(dp) :: ax(100,100), bx(100), xx(100)
      real(dp) :: xpair
!     net pair group  production w/ cons. mass.
      ! Summed factor for multi group
      real(dp) :: xmulti
!     net multi group  production w/ cons. mass.
      ! Rate of self-reaction
      real(dp) :: rself(c_kvec, 20)

      ! flag for self-reaction
      logical :: lself
!
       kk = 1

! PRELIMINARY:  SELF-REACTION FLAG
       lself = .false.

! PRELIMINARY:  make ic point to GAS-MASTER and PRIMARY OF PAIRED SPECIE
!   and count nsol = number of active species groups solved for.
!
       nsol = 0
       loopdim: &
       do nc = 1 , nsdim
         ic = ncsol(nc)
         if ( ic > 0 ) then
           ncsol(nc) = c_nppair(c_npequil(ic), 2)
           nsol = nc
! CHEMSOLVE DEBUG WRITE
!          if(c_kkw.gt.0) write(c_out, 81 ) nc, nsol, ncsol(nc),
!    &        c_tchem(ncsol(nc))
! 81         format('START CHEMSOLVE: nc nsol ic SPECIES =',3i3,a8)
!          if(c_kkw.gt.0) write(c_out,*) nsol
         else
          exit loopdim
         end if
       end do loopdim
!
! ---------------------------------------------
! SUMMATION OF RLOSS - CHEMICAL LOSSES AND CROSS-PRODUCTS
! ---------------------------------------------
!
!  -----------------------
!  PRELIMINARY:  ESTABLISH LIST OF LINKED SPECIES
!  -----------------------
!  nsol = number of pair groups to be solved for (set above)
!  ncsol(n) = ic of head of each pair group to be solved for (input abov
!  nsolv = number of species to be solved for
!          (includes pairs and multi-solve)
!
! ncsolv(i) = ic of each species in order (ncsol(1) and paired, ncsol(2)
!
! nssolv(i) = is of each species = multi-species group for ncsolv
!
! Note:  loop over nsolv automatically solves for multiple-species group
!         as well as single pair grouping
       nsolv = 0
       do is = 1 , nsol
         nsolv = nsolv + 1 + c_nppair(ncsol(is), 3 )
       end do

       nc = 0
       do is = 1 , nsol
         ic = ncsol(is)
         if ( ic > 0 ) then
           do i = 1 , (c_nppair(ic,3)+1)
             icc = ic
             if ( i > 1 ) then
               icc = c_nppair(ic,i+2)
             end if
             nc = nc+1
             ncsolv(nc) = icc
             nssolv(nc) = is
           end do
         end if
       end do


! PRELIMINARY:  FLAG FOR EXPONENTIAL DECAY SOLUTION
!   Use expo decay only for single species solution (unpaired, no aq.)
!   (FUTURE DO.  Not included yet.)

       llexpo(kk) = .false.
       if ( c_lexpo(kk) ) then
         if ( (nsolv == 1) .and. (c_nequil(ncsol(1))== 0) .and. &
              (c_tchem(ncsol(1) ) /= '    H2O2') .and. &
              (.not. c_lsts(ncsol(1))) ) llexpo(kk) = .true.
       end if
!

! PRELIMINARY: CALCULATE REACTION RATES,RP and RL  FOR PRODUCT REACTIONS
! ASSOCIATED WITH SPECIES (i.e. that are sources, not sinks)
!
       do nc = 1 , nsolv
         ics = ncsolv(nc)
         icpair = c_nppair(ics,2)
         if ( c_nnrchp(ics) > 0 ) then
           do i = 1 , c_nnrchp(ics)
             nr = c_nrchmp(ics,i)
             call brpro(nr)

! CHEMSOLVE DEBUG WRITE
!             if(c_kkw.gt.0.   and.nsol.gt.1) then
! c           if(c_kkw.gt.0.   and.c_tchem(ics).eq.'    HCHO') then
!               write(c_out,1001) nr,(c_treac(j,nr),j=1,5),ics
!    *         , c_tchem(ics), c_oddhx(nr), c_pronox(nr)
!             end if

           end do
         end if
       end do
!
! ZERO RPRO, RLOSS, XRP, CPRO.  (XRM, XRRM for multisolve) (
!      (RPPAIR, RLPAIR, XRPPAIR, XRRPAIR for pair group sums)
!
       do i = 1 , nsolv
         rpro(kk,i) = d_zero
         rloss(kk,i) = d_zero
         xrp(kk,i) = d_zero
         xrm(kk,i) = d_zero
         xrrm(kk,i) = d_zero
         rpm(kk,i) = d_zero
         rlm(kk,i) = d_zero
         rself(kk,i) = d_zero
         do ii = 1 , nsolv
           cpro(kk,i,ii) = d_zero
           cpm(kk,i,ii) = d_zero
         end do
       end do
       xrppair(kk) = d_zero
       xrrpair(kk) = d_zero
       rpmulti(kk) = d_zero
       rlmulti(kk) = d_zero

!  -----------------
!  LOOP TO CALCULATE CHEM. LOSS RATES AND CROSS-PRODUCTS
!  -----------------
       do nc = 1, nsolv
         ics = ncsolv(nc)
         iscs = nssolv(nc)
         icpair = c_nppair(ics,2)
!
! ESTABLISH RPRO, RLOSS AND XRP FOR THE 'BASE' SPECIES
         rpro(kk,nc) = rpro(kk,nc) + rrp(kk, ics) + c_xcin(kk,ics)
         rloss(kk,nc) = rloss(kk,nc) + rrl(kk, ics)
         xrp(kk,nc) = xrp(kk,nc) + xc(kk,ics)

! TEMPORARY CHEMSOLVE DEBUG WRITE
! c        if(c_kkw.gt.0   .and.nsol.gt.1)
!        if(c_kkw.gt.0                 )
!    *      write(c_out, 91) c_tchem(ics), rrp(c_kkw,ics),
!    *        c_xcin(c_kkw,ics), rpro(c_kkw, nc)
!    *      ,rrl(c_kkw,ics), rloss(c_kkw, nc)
! 91       format(' START CHEMSOLV: IC RRP XXO RPRO RRL RLOSS= ',a8,/,
!    *      5(1pe10.3))
! TEMPORARY DEBUG ADD 2009
!        if(c_kkw.gt.0                 )
!    &    write(43,*) 'NC (nsolv), rpro(nc)=', nc, nsolv, rpro(kk,nc)

! ADD ALL AQUEOUS-EQUILIBRIUM SPECIES INTO SUMMED RPRO, RLOSS AND XRP.
! CONVERTING AQUEOUS INTO GAS UNITS (AVOGADRL)
! Also include RAINOUT as loss.
         if ( c_nequil(ics) > 0 ) then
           do neq = 1 , c_nequil(ics)
             ic = c_ncequil(ics,neq)
             xrp(kk,nc) = xrp(kk,nc) + xc(kk,ic)*c_h2oliq(kk)*avogadrl
             rpro(kk,nc) = rpro(kk,nc) + rrp(kk,ic)
             rloss(kk,nc) = rloss(kk,nc)+rrl(kk,ic) + &
                            c_rainfr(kk) * xc(kk,ic)*c_h2oliq(kk)*avogadrl
! TEMPORARY CHEMSOLVE DEBUG WRITE
!            if(c_kkw.gt.0              )
! c            if(c_kkw.gt.0.and.nsol.gt.1)
! c           if(c_kkw.gt.0.   and.c_tchem(ics).eq.'    HCHO')
!    *          write(c_out, 91) c_tchem( ic), rrp(c_kkw, ic),
!    *            c_xcin(c_kkw, ic), rpro(c_kkw, nc)
!    *      ,rrl(c_kkw,ic), rloss(c_kkw, nc)
! TEMPORARY DEBUG ADD 2009
!        if(c_kkw.gt.0                 )
!    &    write(43,*) 'NC (nsolv), rpro(nc)=', nc, nsolv, rpro(kk,nc)
           end do
         end if
! END EQUILIBRIUM SUMMATION.

! CHEMSOLVE DEBUG WRITE
! c        if(c_kkw.gt.0  .and.nsol.gt.1)
!        if(c_kkw.gt.0                )
!    *      write(c_out,105) c_tchem(ics),
!    *      xrp(c_kkw,nc), rpro(c_kkw,nc), rloss(c_kkw,nc)
! 105      format(' START CHEMSOLVE: SPECIES, XRP, RPRO, RLOSS=',
!    *            /,a8,2x,3(1pe10.3))
!
! ADD INITIAL SPECIES XRP, RPRO, RLOSS TO XRPPAIR, RPPAIR, RLPAIR
!  IF PAIR GROUP HAS >3 MEMBERS AND NO MULTISOLVE (FOR NORMALIZATION)

!        if(nsolv.ge.3.and.nssolv(nsolv).eq.1) then
         if ( nsolv >= 3 .and. nsol == 1 ) then
           xrppair(kk) = xrppair(kk) + xrp(kk,nc) * c_pairfac(ics)
           rppair(kk,icpair) = rppair(kk,icpair) + rpro(kk,nc) * c_pairfac(ics)
           rlpair(kk,icpair) = rlpair(kk,icpair) + rloss(kk,nc) * c_pairfac(ics)
! CHEMSOLVE DEBUG WRITE
!            if(c_kkw.gt.0)
!    *         write(c_out,104) c_pairfac(ics),
!    *          xrppair(kk), rppair(kk,icpair), rlpair(kk,icpair)
! 104             format(' START PAIR SUM:  SPECIES PAIRFAC; ',
!    *                ' XRPAIR, RP, RL =',/,4(1pe10.3))

                            !if(nsolv.ge.3.and.nsol.eq.1         ) then
         end if

! ADD INITIAL SPECIES XRP, RPRO, RLOSS TO XRM, RPM, RLM: for MULTISOLVE
!  (note:  no PAIRFAC, different from PAIR NORMALIZATION)

         if ( nsol > 1 ) then
           xrm(kk,iscs) = xrm(kk,iscs) + xrp(kk,nc)
           rpm(kk,iscs) = rpm(kk,iscs) + rpro(kk,nc)
           rlm(kk,iscs) = rlm(kk,iscs) + rloss(kk,nc)
           rpmulti(kk) = rpmulti(kk) + rpro(kk,nc) * c_multfac(ics)
           rlmulti(kk) = rlmulti(kk) + rloss(kk,nc) * c_multfac(ics)
! CHEMSOLVE DEBUG WRITE
!            if(c_kkw.gt.0) write(c_out,204)
!    *          xrm(c_kkw,iscs) , rpm(c_kkw,iscs)     , rlm(c_kkw,iscs)
!    *         ,rpmulti(c_kkw), rlmulti(c_kkw)
! 204             format(' START PAIR SUM:  ',
!    *                ' XRPAIR, RP, RL =',/,5(1pe10.3))

         end if

! ADD LOSS REACTIONS AND CROSS-PRODUCT REACTIONS TO RLOSS,RPRO, CPRO.
!
! ALSO SET SELF-REACTION FLAG (lself)
!
! ALSO SET FLAG FOR SECOND REACTANT ALSO INCLUDED IN SPECIES LIST (nc2)
!     (pair or multisolve.  Important for NO+O3->NO2.)

         if ( c_nnrchem(ics) > 0 ) then

! SET INDICES
! FEBRUARY 2005 CHANGE - icr1=npequil is before if(icr2.gt.0) BUG FIX.
           do i = 1 , c_nnrchem(ics)
             nr = c_nrchem(ics,i)
             icr1 = c_reactant(nr,1)
             icr2 = c_reactant(nr,2)
             icr1 = c_npequil(icr1)
             ! index to count loss from 2nd reactant
             nc2 = 0
             if ( icr2 > 0 ) then
               icr2 = c_npequil(icr2)
               if ( icr1 == ics .and. icr2 == ics) lself = .true.
!  FEB 2005OPTION:
!     IF REACTANTS ARE IN SAME PAIR GROUP, SET SELF-REACTION FLAG
!
!  FUTURE DO, FIX SELF-REACTION.
!     (  In SELF-REACTION, do not set 2nd reactant - it messes up CPRO
!          unless CPRO algorithm changed. )
!
               if ( c_nppair(icr1,2) == c_nppair(icr2,2)) lself = .true.
               do ncc = 1 , nsolv
                 if ( ncc /= nc ) then
                   if ( ncsolv(ncc) == icr1 .or. ncsolv(ncc) == icr2) then
                     nc2=ncc
                     ics2 = ncsolv(ncc)
                   end if
                 end if
               end do
             end if

! IF REACTION IS PARAMETERIZED RO2-RO2 SET SELF-REACTION FLAG
             if ( c_nrk(nr) == -13 ) lself = .true.

! CHEMSOLVE DEBUG WRITE
! c            if(c_kkw.gt.0   .and.nsol.gt.1) then
!            if(c_kkw.gt.0                 ) then
!              write(c_out,1001) nr,(c_treac(j,nr),j=1,5)
!    *         , ics,c_tchem(ics) , c_oddhx(nr,1), c_pronox(nr)
! 1001    format('REACTION #',i4,': ',a8,'+',a8,'=>',a8,',',a8,',',a8,/,
!    *     ' KEY SPECIES =',i4,2x,a8,'  ODD-H=',f8.2,'  PRONOX=',f8.2)
!            end if

! CALL BRREAC - to establish reaction rate
             call brreac(nr)

! ADD LOSS FOR FIRST REACTANT
             rloss(kk,nc) = rloss(kk,nc) + c_rr(kk,nr)

!  stoiloss OPTION:
! IF SELF-REACTION: ADD AGAIN.  (2nd reactant index is zero)

             if ( icr1 == icr2 ) then
               rloss(kk,nc) = rloss(kk,nc) + c_rr(kk,nr)
               rself(kk,nc) = rself(kk,nc) + d_two*c_rr(kk,nr)
             end if

! IF PARAMETERIZED RO2: add to RSELF.  (note: rate const includes 2x for
             if ( c_nrk(nr) == -13 ) then
               rself(kk,nc) = rself(kk,nc) + c_rr(kk,nr)
             end if

! CHEMSOLVE DEBUG WRITE
! c            if(c_kkw.gt.0  .and.nsol.gt.1)
!            if(c_kkw.gt.0                )
!    *        write(c_out,108) c_tchem(ics),
!    *          rloss(c_kkw,nc), c_rr(c_kkw,nr)
! 108          format(' CHEMSOLVE LOSS FOR MAIN SPECIES:  IC = ',
!    *           a8,/,
!    *           '    RLOSS , RR = ',2(1pe10.3))

! TEMPORARY DEBUG ADD   xc(kk,icr1), xc(kk,icr2), ratek(kk, nr)
!             if(c_kkw.gt.0) then
!                write(c_out, *  ) nr, icr1, icr2
!                if(icr1.gt.0) write(c_out,*) xc(kk,icr1)
!                if(icr2.gt.0) write(c_out,*) xc(kk,icr2)
!                if(  nr.gt.0) write(c_out,*) ratek(kk,nr)
!             end if

! SECOND SPECIES OPTION:
! ADD LOSS OF 2ND REACTANT FOR DIFFERENT SPECIES. (for NO+O3->NO2).
! ADD TO RLOSS1 ALSO (which may  have been written before
!    - RLOSS1 only excludes CPRO and PSEUDO-SOLUTION.
!
! NOTE: omit stoiloss, which adjusts only for main species
!       appearing in reactant and product.
!
             if ( nc2 > 0 ) then
               rloss(kk,nc2) = rloss(kk,nc2) + c_rr(kk,nr)
               rloss1(kk,nc2)=rloss1(kk,nc2) + c_rr(kk,nr)

!  CHEMSOLVE DEBUG WRITE
! c              if(c_kkw.gt.0  .and.nsol.gt.1)
!              if(c_kkw.gt.0                )
!    *          write(c_out, 109) c_tchem(ics),
!    *           c_tchem(icr2), rloss(c_kkw,nc2), c_rr(c_kkw,nr)
! 109            format(' CHEMSOLVE LOSS FOR SECOND SPECIES: IC, IC2 =',
!    *           a8,2x,a8,/,
!    *           '    RLOSS2, RR = ',2(1pe10.3))

             end if

! ADD PRODUCTS TO CPRO or RPRO.
! CPRO MATRIX  (kk,reactant,product).  (note prodarr=gas-master product)
!
             do ncc = 1 , nsolv
               if ( c_prodarr(nr,ncsolv(ncc)) /= 0 ) then
                 icc = ncsolv(ncc)
! Adjust LOSS if PRODUCT EQUALS REACTANT, skip PRO.
                 if ( ncc == nc .or. ncc == nc2 ) then
                   stoicx = c_prodarr(nr,ncsolv(ncc))
                   if ( stoicx > d_one) stoicx = d_one
                   rloss(kk,ncc)=rloss(kk,ncc) - c_rr(kk,nr)*stoicx
                   if ( ncc == nc2 ) then
                     rloss1(kk,ncc) = rloss1(kk,ncc) - c_rr(kk,nr)*stoicx
                   end if
                 else

! ADD TO CPRO - ONLY IF SPECIES ARE DIRECT PAIRS
!   ALSO IF MULTI.
!   (MULTI CPRO is added to RPRO for pair solution below,t not here -
!     to avoid doublecounting in RPM.)

                   if ( (c_nppair(ics,1) == icc .or. &
                         c_nppair(icc,1) == ics) .or. &
                         (nssolv(nc) /= nssolv(ncc)) ) then
                     cpro(kk,nc,ncc) = cpro(kk,nc,ncc) + &
                                       c_rr(kk,nr)*c_prodarr(nr,ncsolv(ncc))
! TEMPORARY TEST DEBUG WRITE
!                 if(c_kkw.gt.0  .and.nsol.gt.1) write(c_out,1103)
!    *              nc,ncc,cpro(c_kkw,nc,ncc)
! 1103                format('NC, NCC, CPRO=', 2i5,8(1pe10.3))

                   else
! ADD TO RPRO IF NOT DIRECT PAIR
                     rpro(kk,ncc) = rpro(kk,ncc) + &
                                    c_rr(kk,nr)*c_prodarr(nr,ncsolv(ncc))
! TEMPORARY TEST DEBUG WRITE
! c                 if(c_kkw.gt.0  .and.nsol.gt.1) write(c_out,1104)
!                 if(c_kkw.gt.0                ) write(c_out,1104)
!    *              nc,ncc,rpro(c_kkw,ncc)
! 1104                format('NC, NCC, RPRO=', 2i5,8(1pe10.3))

                   end if

!  TEMPORARY TEST DEBUG WRITE
!                   if(c_kkw.gt.0  .and.nsol.gt.1) write(c_out,1101)
!    *              nc, ncc, ics, ncsolv(ncc), nr, c_rr(c_kkw,nr),
!    *              c_prodarr(nr,ncsolv(ncc))
! 1101                format(' CPRO FORMATION: NC NCC IC(nc) IC(ncc)',
!    *                ' NR RR PRODARR=',/, 5i5, 2(1Pe10.3))

                                   !if(ncc.ne.nc) then
                 end if

!   CPRO FROM SECOND REACTANT
!   FEBRUARY 2005 CHANGE:
!     IF DIRECT PAIR, ADD TO CPRO AND SUBTRACT FROM RPRO
!       (it should have just been added to RPRO for 1st reactant)
!     OTHERWISE, SKIP.
!      (Note:  for MULTI, CPRO is recorded and added to RPRO for PAIRSOL
!       This must be done just once, for 1st reactant, to avoid double c
!
! CHANGE
                 if ( nc2 > 0 ) then
                   if ( (c_nppair(ics2,1) == icc .or. &
                         c_nppair(icc,1) == ics2) ) then
! DIRECT PAIR:   ADD 2ND REACTANT CPRO, ADJUST RPRO. (NCPRO CUT)
                     cpro(kk,nc2,ncc) = cpro(kk,nc2,ncc) + &
                                        c_rr(kk,nr)*c_prodarr(nr,ncsolv(ncc))
                     rpro(kk,ncc) = rpro(kk,ncc) - &
                                    c_rr(kk,nr)*c_prodarr(nr,ncsolv(ncc))
! TEMPORARY TEST DEBUG WRITE
! c                 if(c_kkw.gt.0  .and.nsol.gt.1) write(c_out,1105)
!                 if(c_kkw.gt.0                ) write(c_out,1105)
!    *              nc,nc2,ncc,cpro(c_kkw,nc2,ncc), rpro(c_kkw,ncc)
! 1105                format('NC,NC2, NCC, CPRO,RPRO(NCC)=',
!    &                 3i5,8(1pe10.3))

!  INTERNAL BUT NOT DIRECT:  DO NOTHING
!                else             !if( (c_nppair(ics2,1).eq.icc then
!                  if   (nssolv(nc).eq.nssolv(ncc)) then
!  MULTI:  DO NOTHING
!                  else          !if   (nssolv(nc).eq.nssolv(ncc)) then

! END CPRO FROM 2ND REACTANT
                   end if

!  TEMPORARY TEST DEBUG WRITE
!                   if(c_kkw.gt.0  .and.nsol.gt.1) write(c_out,1101)
!    *           nc2, ncc, ncsolv(nc2), ncsolv(ncc),
!    *           nr, c_rr(c_kkw,nr),
!    *           c_prodarr(nr,ncsolv(ncc))

                 end if
               end if
             end do

! END LOOP - CPRO MATRIX

! CALCULATE NET PRODUCTION AND LOSS FOR PAIR GROUP
!  (FOR NORMALIZATION OF GROUP w>3 MEMBERS)
             if(nsolv.ge.3.and.nsol.eq.1         ) then
               xpair = 0.
               if(c_nppair(icr1,2).eq.icpair)                           &
     &              xpair = xpair - c_pairfac(icr1)
               if(icr2.gt.0) then
                 if(c_nppair(icr2,2).eq.icpair)                         &
     &            xpair =  xpair - c_pairfac(icr2)
               end if
               do ncc=1,nsolv
                  xpair = xpair + c_prodarr(nr,ncsolv(ncc))             &
     &                                   *c_pairfac(ncsolv(ncc))
                                 !do ncc=1,nsolv
               end do


               if(xpair.lt.0.) then
!                do kk=1,c_kmax        ! kk vector loop
                   rlpair(kk,icpair)  = rlpair(kk,icpair)               &
     &                                     -xpair*c_rr(kk,nr)
!                end do               ! kk vector loop
                                     !if(xpair.lt.0.) then
               end if

               if(xpair.gt.0.) then
!                do kk=1,c_kmax        ! kk vector loop
                   rppair(kk,icpair) =rppair(kk,icpair)                 &
     &                       +xpair*c_rr(kk,nr)
!                end do               ! kk vector loop
                                     !if(xpair.lt.0.) then
               end if

! CHEMSOLVE DEBUG WRITE
!              if(c_kkw.gt.0) write (c_out,110) xpair, c_rr(kk,nr),
!    *             rlpair(c_kkw,icpair), rppair(c_kkw,icpair)
! 110            format(' CHEM REACTION ADDED TO PAIR GROUP SUM:',/,
!    *              ' FACTOR, RR, RLPAIR, RPPAIR =', 4(1pe10.3))

                                !if(nsolv.ge.3.and.nsol.eq.1 ) then
             end if

! CALCULATE NET PRODUCTION AND LOSS FOR PAIR GROUP
!  FOR MULTISOLVE (AND NORMALIZATION OF GROUP w>3 MEMBERS)
!
             if(nsol.gt.1                        ) then
               isr1 = nssolv(nc)
               isr2 = 0
               if(nc2.gt.0) then
                 isr2=nssolv(nc2)
                                !if(nc.gt.0) then
               end if

! MULTISOLVE DEBUG WRITE
!            if(c_kkw.gt.0) then
!              write(c_out,1201) nr,(c_treac(j,nr),j=1,5),ics
!    *            , c_tchem(ics)
! 1201    format('REACTION #',i4,': ',a8,'+',a8,'=>',a8,',',a8,',',a8,/,
!    *     ' KEY SPECIES =',i4,2x,a8)
!               write(c_out,*) nc, nc2, isr1, isr2
!            end if

! LOOP THROUGH PAIR GROUPS
               xmulti = 0.
               do is=1,nsol
                 ic=ncsol(is)

!   ESTABLISH NET PRO/LOSS FOR PAIR GROUP
                 xpair = 0.
                 if(is.eq.isr1)  xpair = xpair - 1.
                 if(is.eq.isr2)  xpair = xpair - 1.

                 if(is.eq.isr1)  xmulti= xmulti- c_multfac(ic)
                 if(is.eq.isr2)  xmulti= xmulti- c_multfac(ic)

! ERROR HERE  - THIS WAS c_nppair(icpair,.) THROUGHOUT LOOP
!             -  SHOULD BE c_nppair(ic,..)

                 do iss=1,(c_nppair(ic    ,3)+1)
                  icc=ic
                  if(iss.gt.1) icc=c_nppair(ic    ,iss+2)
                  xpair = xpair + c_prodarr(nr,      (icc))
                  xmulti= xmulti+ c_prodarr(nr,      (icc))             &
     &                           *c_multfac(icc)

                                   !do ncc=1,nsolv
                 end do

! MULTISOLVE DEBUG WRITE
!                if(c_kkw.gt.0) write(c_out,1211) is,c_tchem(ic), xpair
! 1211             format(' MULTISOLVE SETUP: IS TCHEM XPAIR XMULTI =',
!    *                i3,2x,a8,2(1pe10.3))


!   ADD TO RLM LOSS
                 if(xpair.lt.0.) then
!                  do kk=1,c_kmax        ! kk vector loop
                     rlm(kk,is)      = rlm(kk,is)     -xpair*c_rr(kk,nr)
!                  end do               ! kk vector loop

! MULTISOLVE DEBUG WRITE
!                  if(c_kkw.gt.0) write(c_out,1212)rlm(c_kkw,is)
!    *                      ,c_rr(c_kkw,nr)
! 1212               format(' ADD -XPAIR*RR TO RLM: RLM, RR='
!    *                              ,2(1pe10.3))

! SUBTRACT CROSS-LOSS FROM CPM.  (add negative XPAIR)
!   (NOTE:  Just one cross-loss;
!     2nd cross-loss will be counted when loop reaches the other reactan
!
                   if(isr1.gt.0.and.isr1.ne.is) then
!                    do kk=1,c_kmax        ! kk vector loop
                       cpm(kk,isr1,is) = cpm(kk,isr1,is)                &
     &                                     + xpair*c_rr(kk,nr)
!                      cpm(kk,is,isr1) = cpm(kk,is,isr1)
!    *                                    + xpair*c_rr(kk,nr)
!                    end do               ! kk vector loop

! MULTISOLVE DEBUG WRITE
!                  if(c_kkw.gt.0) write(c_out, 1213) isr1,
!    *                cpm(kk,isr1,is), cpm(kk,is, isr1)
! 1213               format(' SUBTRACT XPAIR*RR FROM CPM: ISR1,CP,CP=',
!    *                     2x,i4,2(1pe10.3))


                                       !if(isr1.gt.0) then
                   end if
                   if(isr2.gt.0.and.isr2.ne.is) then
!                    do kk=1,c_kmax        ! kk vector loop
                       cpm(kk,isr2,is) = cpm(kk,isr2,is)                &
     &                                       + xpair*c_rr(kk,nr)
!                      cpm(kk,is,isr2) = cpm(kk,is,isr2)
!    *                                       + xpair*c_rr(kk,nr)
!                    end do               ! kk vector loop

! MULTISOLVE DEBUG WRITE
!                  if(c_kkw.gt.0) write(c_out, 1214) isr2,
!    *                cpm(kk,isr2,is), cpm(kk,is, isr2)
! 1214               format(' SUBTRACT XPAIR*RR FROM CPM: ISR2,CP,CP=',
!    *                     2x,i4,2(1pe10.3))

                                       !if(isr2.gt.0) then
                   end if

!   ADJUSTMENT FOR SELF-REACTION (includes 2 reactants in one pair group
!     (Back-Euler: dR/dx for rate kx^2 is 2kx;  loss per reaction=2.
!      So total loss is 2R;  sensitivity is 4 R.
!      Add 2R to RPM, 4R to RLM.)
!     HERE:  XPAIR*R already added to RLM.  Add again to RLM, RPM.
!
                   if(isr1.eq.is.and.isr2.eq.is) then
!                    do kk=1,c_kmax        ! kk vector loop
                       rlm(kk,is)        = rlm(kk,is)                   &
     &                                         - xpair*c_rr(kk,nr)
                       rpm(kk,is)        = rpm(kk,is)                   &
     &                                         - xpair*c_rr(kk,nr)
!                    end do               ! kk vector loop
                                      !if(isr1.eq.is.and.isr2.eq.is)
                   end if

                                       !if(xpair.lt.0.) then
                 end if

! ADD TO RPM
                 if(xpair.gt.0.) then
!                  do kk=1,c_kmax        ! kk vector loop
                     rpm(kk,is)      = rpm(kk,is)   + xpair*c_rr(kk,nr)
!                  end do               ! kk vector loop

! MULTISOLVE DEBUG WRITE
!                  if(c_kkw.gt.0) write(c_out,1222)rpm(c_kkw,is)
!    *                        , c_rr(c_kkw,nr)
! 1222               format(' ADD +XPAIR*RR TO RPM: RPM, RR='
!    *                                 ,2(1pe10.3))


! ADD TO CPM  CROSS-PRO.
                   if(isr1.gt.0.and.isr1.ne.is) then
!                    do kk=1,c_kmax        ! kk vector loop
                       cpm(kk,isr1,is)    = cpm(kk,isr1,is)             &
     &                                      + xpair* c_rr(kk,nr)
!                    end do               ! kk vector loop

! MULTISOLVE DEBUG WRITE
!                  if(c_kkw.gt.0) write(c_out, 1223) isr1,
!    *                cpm(kk,isr1,is)
! 1223               format(' ADD      XPAIR*RR TO   CPM: ISR1,CP,CP=',
!    *                     2x,i4,2(1pe10.3))

                                       !if(isr1.gt.0) then
                   end if
                   if(isr2.gt.0.and.isr2.ne.is) then
!                    do kk=1,c_kmax        ! kk vector loop
                       cpm(kk,isr2,is)    = cpm(kk,isr2,is)             &
     &                                      + xpair* c_rr(kk,nr)
!                    end do               ! kk vector loop

! MULTISOLVE DEBUG WRITE
!                  if(c_kkw.gt.0) write(c_out, 1224) isr2,
!    *                cpm(kk,isr2,is)
! 1224               format(' ADD      XPAIR*RR TO   CPM: ISR2,CP   =',
!    *                     2x,i4,2(1pe10.3))

                                       !if(isr2.gt.0) then
                   end if

                                    !if(xpair.gt.0.) then
                 end if


! CHEMSOLVE DEBUG WRITE
!                if(c_kkw.gt.0) write (c_out,211) xpair, c_rr(kk,nr),
!    *               rlm(c_kkw,is)       , rpm(c_kkw,is)
! 211              format(' CHEM REACTION ADDED TO PAIR GROUP SUM:',/,
!    *             ' FACTOR, RR, RLM   , RPM    =', 4(1pe10.3))

                            !do is=1,nsol
               end do
! END LOOP THROUGH PAIR GROUPS
!
! MULTI GROUP SUM
               if(xmulti.lt.0.) then
!                do kk=1,c_kmax        ! kk vector loop
                   rlmulti(kk)  = rlmulti(kk)                           &
     &                                     -xmulti*c_rr(kk,nr)
!                end do               ! kk vector loop
                                     !if(xmulti.lt.0.) then
               end if

               if(xmulti.gt.0.) then
!                do kk=1,c_kmax        ! kk vector loop
                   rpmulti(kk) =rpmulti(kk)+xmulti*c_rr(kk,nr)
!                end do               ! kk vector loop
                                     !if(xmulti.gt.0.) then
               end if

! CHEMSOLVE DEBUG WRITE
!                if(c_kkw.gt.0) write (c_out,210) xmulti,c_rr(kk,nr),
!    *               rlmulti(c_kkw)      , rpmulti(c_kkw)
! 210              format(' CHEM REACTION ADDED TO MULTI GROUP SUM:',/,
!    *             ' FACTOR, RR, RLM   , RPM    =', 4(1pe10.3))

                       !if(nsol.gt.1                        ) then
             end if
! END CALCULATE NET PRODUCTION AND LOSS FOR PAIR GROUP

                  ! do  i=1,c_nnrchem(ics)
           end do
                  !  c_nnrchem(ics).gt.0
         end if
! END - ADD LOSS REACTIONS AND CROSS-PRODUCTS

! NONSTEADY STATE ADJUSTMENT FOR PAIR GROUP SUM
!   (ahead of STEADY STATE ADJUSTMENT to use RLOSS=0)
!   (note RPPAIR already includes XXO)
!
         if(nsolv.ge.3.and.nsol.eq.1         ) then
!          do kk=1,c_kmax      ! kk vector loop
            if(.not.c_lsts(ics).or.rloss(kk,nc).eq.0)                   &
     &          rlpair(kk,icpair)   = rlpair(kk,icpair)                 &
     &                   + xrp(kk,nc)*c_pairfac(ics)
            if(rloss(kk,nc).le.0.)                                      &
     &          rlpair(kk,icpair)   = rlpair(kk,icpair)                 &
     &                   + 1.0e-08   *c_pairfac(ics)
!          end do                       ! kk vector loop
                          !if(nsolv.ge.3.and.nsol.eq.1         ) then
         end if

! CHEMSOLVE DEBUG WRITE
!        if(c_kkw.gt.0) write(c_out, 107) c_pairfac(ics), xrp(c_kkw,nc),
!    *                  rlpair(c_kkw,icpair)
! 107        format(' PRIOR CONC.   ADDED TO PAIR GROUP SUM:',/,
!    *            ' FACTOR, XRP, RLPAIR =', 4(1pe10.3))

! NONSTEADY STATE ADJUSTMENT FOR MULTISOLVE SUM
!   (ahead of STEADY STATE ADJUSTMENT to use RLOSS=0)
!
         if(nsol.gt.1                        ) then
!          do kk=1,c_kmax      ! kk vector loop
            if(.not.c_lsts(ics).or.rloss(kk,nc).eq.0) then
                rlm(kk,iscs)          = rlm(kk,iscs)                    &
     &                   + xrp(kk,nc)
                rlmulti(kk)           = rlmulti(kk)                     &
     &                   + xrp(kk,nc)*c_multfac(ics)
                         !if(.not.c_lsts(ics).or.rloss(kk,nc).eq.0) then
            end if
            if(rloss(kk,nc).le.0.)  then
                rlm(kk,iscs)          = rlm(kk,iscs)                    &
     &                   + 1.0e-08
                rlmulti(kk)           = rlmulti(kk)                     &
     &                   + 1.0e-08   *c_multfac(ics)
                           !if(rloss(kk,nc).le.0.)  then
            end if
!          end do                       ! kk vector loop
                          !if(nsol.gt.1                        ) then
         end if

! CHEMSOLVE DEBUG WRITE
!        if(c_kkw.gt.0) write(c_out, 207) c_pairfac(ics), xrp(c_kkw,nc),
!    *                  rlm(c_kkw,iscs)
!        if(c_kkw.gt.0) write(c_out,*) ics,nc,iscs
! 207        format(' PRIOR CONC.   ADDED TO PAIR GROUP SUM:',/,
!    *            ' FACTOR, XRP, RLPAIR =', 4(1pe10.3))


! NONSTEADY STATE ADJUSTMENT:  IF NONSTEADY STATE OR ZERO RLOSS, ADD XRP
!  (EQUIVALENT TO RL/XR + 1).
!  (NOTE:  STEADY-STATE OPTION STILL INCLUDES XXO IN RPRO.
!   FOR STEADY STATE XXO SHOULD EQUAL EITHER EMISSIONS OR ZERO.)
!    (XXO SET IN PRELUMP)

! WITH ZERO PROTECT FOR RLOSS

!        do kk=1,c_kmax      ! kk vector loop
          if(.not.c_lsts(ics).or.rloss(kk,nc).eq.0)                     &
     &          rloss(kk,nc) = rloss(kk,nc) + xrp(kk,nc)
          if(rloss(kk,nc).le.0.) rloss(kk,nc) = 1.0e-08
!        end do                       ! kk vector loop


!  (OPTION:  FOR A SELF-REACTION (stoiloss>1, e.g. HO2+HO2, stoiloss=2.)
!   AN EXACT LINEARIZED NR SOLUTION WOULD REQUIRE
!   RLOSS=+2*RR*STOILOSS, RPRO=+RR*STOILOSS. (d/dR = twice loss rate.)
!   TO IMPLEMENT THIS, IF STOILOSS>1, ADD ADDITIONAL RR*STOILOSS
!   TO BOTH RLOSS AND RPRO, WITHIN LOOP 125 (and 225 for twosolve).

!   This is cut because IT MAY SCREW HO2+HO2 REACTIONS.
!  )

!  SAVE RLOSS1, RPRO1
!     =RPRO without CPRO; RLOSS w/o internal solution adjustments.

!        do kk=1,c_kmax      ! kk vector loop
           rloss1(kk,nc) = rloss(kk,nc)
           rpro1(kk,nc) = rpro(kk,nc)
!        end do                    ! kk vector loop

! TEMPORARY DEBUG ADD 2009
!        if(c_kkw.gt.0                 )
!    &    write(43,*) 'NC (nsolv), rpro1(nc)=', nc, nsolv, rpro1(kk,nc)


                   !  do nc=1, nsolv
       end do

!  ---------------------
!  END LOOP TO CALCULATE CHEM. LOSS RATES AND CROSS-PRODUCTS
!  ---------------------

! SET SELF-REACTION FLAG:  false if self-reaction is insignificant
!       (ADDED 408 APRIL 2008)
!       (note future option:  save history and use to prevent oscill.)
!       (note - this prevents NO3-N2O5 error, but hard-wired NO3 retaine
!  LSELF OPTION: 2009 CORRECTION - skip for iter=1)
!
!
!     if(lself) then
!     if(lself.and.c_iter.gt.2) then
      if(lself.and.c_iter.gt.1) then
        lself=.FALSE.
        do nc=1,nsolv
         if(rself(kk,nc).gt.0.33*rloss1(kk,nc)) lself=.TRUE.

! TEMPORARY DEBUG WRITE 408
!        ics = ncsolv(nc)
!       if(c_kkw.gt.0) write(c_out,*)
!    &    'RSELF: tchem, ics, nc, rloss, rself, lself',
!    &      c_tchem(ncsolv(nc)), ncsolv(nc),nc,rloss1(kk,nc),
!    &      rself  (kk,nc), lself

                          !do nc=1,nsolv
        end do
                        !if(lself) then
      end if
! END-  SET SELF-REACTION FLAG
!

!  OPTION:  Add external CPRO to RPRO for multi-species.
!  CURRENT OPTION:
!   Internal XRR will be solved with RPRO from prior values of multi-spe
!   RLOSS already includes loss to other multi-species groups.
!  ALTERNATIVE:
!   subtract CP to multi-species from RLOSS

       if(nsol.gt.1) then
         do nc=1, nsolv
           ics = ncsolv(nc)
           do ncc=1,nsolv
             if(nssolv(ncc).ne.nssolv(nc)) then
!              do kk=1,c_kmax      ! kk vector loop
                 rpro(kk,nc) = rpro(kk,nc) + cpro(kk,ncc,nc)
!              end do              ! kk vector loop
                               !(nssolv(ncc).ne.nssolv(nc))
             end if

                     ! ncc=1, nsolv
           end do

!   CHEMSOLVE DEBUG WRITE - RPRO, RLOSS, CPRO, BEFORE CPRO PAIR ADJUSTME
!     (RPRO1= prior without CP;RPRO includes CP from multi-spec. groups)

! c          if(c_kkw.gt.0.and.nsolv.gt.1  .and.nsol.gt.1) then
!          if(c_kkw.gt.0                               ) then
!             write(c_out,111) c_tchem(ics),
!    *       rpro1(c_kkw,nc),rpro(c_kkw,nc), rloss(c_kkw,nc)
! 111      format('CHEMSOLVE INITIAL VALUES: RPRO1, RPRO+multi,RLOSS= '
!    *        ,/,a8,2x,(8(1pe10.3)))
!           write(c_out,112) (cpro(c_kkw,nc,ncc),ncc=1,nsolv)
! 112       format(' CPRO(nc,ncc),ncc=1,nsolv):',/,(8(1pe10.3)))
!          end if         !if(c_kkw.gt.0.and.nsolv.gt.1)


                     !  do nc=1, nsolv
         end do
                   !if(nsol.gt.1) then
       end if


! ---------------------------------------------
! END - SUMMATION OF RLOSS - CHEMICAL LOSSES AND CROSS-PRODUCTS
! ---------------------------------------------

! ---------------------------------------------
! CALCULATE SPECIES CONCENTRATIONS:  INTERNAL PAIRS
! ---------------------------------------------
!
!  THE ALGORITHM:
!   For two interacting species:  A<->B
!   Back-Euler solution:  xr = xrprior * (Pi + CjiPj/Lj)/(Li-CijCji/Lj)
!                            = xrprior * (   Pi'       )/(  Li'      )
!     where Li = prior absol. loss rate + xrprior (non-steady state)
!           Pi = prior production + c_xcin
!           Cji = cross production of i from j
!           Pi', Li' = pseudo-P, L with cross prod'n from paired subspec
!
!     (neg. not possible since Li>Cij, Lj>Cji)
!
!   For a chain of interacting species:  A<->B, A<->C, C<->C2, etc.
!     in order from primary to subspecies:  Cij=0 for j<i
!     CjiPj, etc. is implicit sum over all paired subspecies j
!     Solve from sub-species to primary species Pi'/Li'
!        where Pi', Li' includes Cji, j>i
!     Then solve from primary Xi to subspecies Xj
!      with  Cij from primary Xi updated and added to Pj
!
!   This effectively uses a prior secondary partitioning (C<->C2)
!    to generate primary partitioning (A<->B, A<->C) and primary XR
!    It uses primary (A) to solve for secondary (B, C, etc.)
!      while preserving C<->C2 partitioning (implicit in Pi'/Li')
!
!   FOR MULTISOLVE/NOXSOLVE (STANDARD OPTION):
!    PAIR SOLUTION is normalized to keep original within-pair sum unchan
!    NOXSOLVE or MULTISOLVE changes pair sums (preserving internal parti
!     based on interaction between pair groups.

!   OPTION for NOXSOLVE/MULTSOLVE:
!    should the PAIR SOLUTION include cross-production from other groups
!    LOSS includes CP to other group.
!    Either subtract prior Cij from Li, or add prior Cij to Lj
!     (ABOVE)
! ------------------------------------

! ---------
! LOOP TO  ADJUST RP, RL FOR SUB-SPECIES CROSS PRODUCTION (PSEUDO-RP, RL
! ---------
!  RPRO, RLOSS ADJUSTED FOR INTERNAL CP PRODUCTION FROM SUB-SPECIES ONLY
!  (This loop automatically includes each multi-species grouping.)
!  (Loop order:  from sub-species to primary species;
!     so that primary species includes subspecies RP with sub-CP adjustm

! (RPRO1, RLOSS1 preserves original RPRO, RLOSS w/o adjustments)

       if(nsolv.gt.1) then
         do nc=(nsolv-1), 1, -1
           ics = ncsolv(nc)
           do ncc=(nc+1), nsolv
             if(nssolv(nc).eq.nssolv(ncc)) then
               icc = ncsolv(ncc)
!              do kk=1,c_kmax      ! kk vector loop
                 rpro(kk,nc) = rpro(kk,nc)                              &
     &            + cpro(kk,ncc,nc) * (rpro(kk,ncc)/rloss(kk,ncc))
                 alpha(kk) =                                            &
     &              cpro(kk,ncc,nc)*(cpro(kk,nc,ncc)/rloss(kk,ncc))
                 rloss(kk,nc) = rloss(kk,nc) - alpha(kk)
                 if(rloss(kk,nc).le.0.) then
                   write(c_out,121 ) c_tchem(ncsol(1)), ncsol(1),       &
     &              nc, ncc, rloss(kk,nc), alpha(kk), cpro(kk,ncc,nc),  &
     &               cpro(kk,nc,ncc), rloss(kk,ncc)
  121              format(/,'MAJOR ERROR IN CHEMSOLVE: ',               &
     &                      'RLOSS = 0 FROM CPRO ADJUSTMENT.',/,        &
     &                      ' ic1, nc, ncc=  ', a8,3i4,/,               &
     &                      ' rloss, alpha, cpro-nc, cpro-ncc, rl-ncc=' &
     &                      ,/, (5(1pe10.3))    )
                   rloss(kk,nc) = rloss(kk,nc) + alpha(kk)
                 end if
!              end do          !kk vector loop

!   CHEMSOLVE DEBUG WRITE - RPRO, RLOSS  AFTER CPRO PAIR ADJUSTMENT
!     (RP, RL adjusted as pseudo-RP, RL with CP from subspecies to prima
!       FINAL RP below will also include CP from primary to subspecies.)

! c              if(c_kkw.gt.0.  and.nsol.gt.1) then
!              if(c_kkw.gt.0.               ) then
!                write(c_out,113) c_tchem(ics), c_tchem(icc),
!    &              nc, ncc, rpro(c_kkw,ncc), rloss(c_kkw,ncc),
!    *             rpro1(c_kkw,nc),rpro(c_kkw,nc),rloss1(c_kkw,nc)
!    *            , rloss(c_kkw,nc)
!    &            ,cpro(c_kkw,ncc,nc), cpro(c_kkw,nc,ncc)
! 113               format(' CHEMSOLVE CP PSEUDO-RP,RL: ',
!    *                   ' FOR   ', a8,'    FROM   ',a8, /,
!    &             ' (nc, ncc =', 2i4,/,
!    &             ' rpro(ncc), rloss=',2(1pe10.3),/,
!    &             'rpro=rpro+cpro(ncc,nc)*rpro(ncc)/rloss(ncc)',/,
!    &             'rloss=rloss-a, a=cpro(ncc,nc)',
!    &                            '*(cpro(nc,ncc)/rloss(ncc)',/
!    *          'RPRO1, RPRO, RLOSS1, RLOSS (alpha cpro ncc-nc nc-ncc)'
!    *              ,/,(8(1pe10.3)))
!
! TEMPORARY DEBUG ADD 2009
!        if(c_kkw.gt.0                 )
!    &    write(43,*) 'NC (nsolv), rpro(nc)=', nc, nsolv, rpro(kk,nc)
!        if(c_kkw.gt.0                 )
!    &    write(43,*) 'rpro(1), rpro(2)    =', rpro(kk,1),rpro(kk,2)
!              end if      ! debug write end (?)

                        ! nssolv(nc)
             end if
                    !ncc=(nc+1), nsolv
           end do
                    !nc=nsolv, 1, -1
         end do
                  ! nsolv.gt.1
       end if



! ---------
!  END LOOP TO ADJUST RP, RL FOR CP
! ---------
!
!
! ---------
!  LOOP TO SOLVE SPECIES CONCENTRATIONS- INTERNAL PAIRS
! ---------
!   Order:  primary-to-subspecies chain among paired species
!   After calculation, add modified CPRO to CP-down-species.
!
       do nc=1, nsolv
         ics = ncsolv(nc)
         is=nssolv(nc)
         icpair = c_nppair(ics,2)

!   BACKWARD EULER SOLUTION FOR SINGLE SPECIES
!    The true equation is =RP/(RL/XR); modified to avoid second divide.
!     (skip from here - move lower)

! c                      do  kk=1,c_kmax      ! kk vector loop
!        if(.not.llexpo(kk)) then
!          xrr(kk, nc)= xrp(kk,nc)*rpro(kk,nc)/rloss(kk,nc)
!        end if       !if(.not.llexpo) then
!                      end do            ! kk vector loop
!
!  EXPONENTIAL DECAY OPTION:  SINGLE SPECIES ONLY.

!  EQUATION:  dc/dt= r-kc, c=Co at t=0. (r=rp/time +emission rate)
!  Ct = r/k + (Co - r/k) exp(-kt)
!  Cavg = r/k + ((Co-r/k)/kt)*(1- exp(-kt))    =  (Co-Cf)/kt + r/k
!       Cf= Co + rt - kt*Cav    --checks
!
! Here, Co = xcin - xcemit
!       rt = rpro-xcin+xcemit
!       kt = (rloss-xrp)/xrp
!
!  Result saved as:
!       xc = Cavg (used for reaction rate calculations)
!        (xrr = Cavg, then turned into Cavg/Cprior 'NEW/OLD' below,,
!                 and used to get xc gas,aq -as in standard back-Euler.)
!       xcfinr = Cf/Cavg  (used in postlump to get xcout)
!       NOTE: xcfinr=1 in BACK-EULER solution.

! NOTE ERROR CORRECTIONS:
!     beta: form A(1-exp) + B(exp) , not A + (B-A)*exp
!        (else large-number error and negative value)
!     ZERO PROTECT for xrr
!     Use back-Euler for very small values.


!                      do  kk=1,c_kmax      ! kk vector loop
         doneexpo(kk) = .FALSE.
         if(llexpo(kk)) then

           if(xrp(kk,nc).gt.0                                           &
     &        .and. ( rloss(kk,nc)-xrp(kk,nc) .gt.0. )                  &
     &        .and. ( rloss(kk,nc)+rpro(kk,nc).gt.1. )                  &
     &                                       ) then

!    alpha = kt =(rloss-xrp)/xrp
           alpha(kk) = rloss(kk,nc)/xrp(kk,nc) - 1.
!
!    beta = rt/kt = (rpro-xcin+xcemit)/alpha
           beta(kk) = (rpro(kk,nc)-c_xcin(kk,ics)+c_xcemit(kk,ics))     &
     &               /alpha(kk)

!    Cf =   r/k + (    Co     - r/k) exp(-kt)
!    Cf =  beta + (xcin-xcemit-beta)*exp(-alpha)
!    NOTE: This must be greater than (xcin-xcemit)
!
! The following line caused LARGE-NUMBER NUMERICAL ERRORS
!            xcfinr(kk,ic) = beta(kk)
!    *          +(c_xcin(kk,ic) - c_xcemit(kk,ic) - beta(kk))
!    *           *exp(0.-alpha(kk))
!
! Corrected:
             xcfinr(kk,ics) = beta(kk) * (1.- exp(0.-alpha(kk)) )       &
     &          +(c_xcin(kk,ics) - c_xcemit(kk,ics)           )         &
     &           *exp(0.-alpha(kk))


!    Cav = (    Co     -Cf)/kt    + r/k
!    Cav = (xcin-xcemit-Cf)/alpha + beta
!
             xrr(kk,nc) = beta(kk)                                      &
     &            +( c_xcin(kk,ics) - c_xcemit(kk,ics) - xcfinr(kk,ics))&
     &          /alpha(kk)
!
! Cf/Cav  - with ZERO PROTECT
             if(xrr(kk,nc).gt.0) then
                xcfinr(kk,ics) = xcfinr(kk,ics)/xrr(kk,nc)

! Done-expo flag. (within ZERO PROTECT loop)
!  OPTION:  protect against wild values
                doneexpo(kk) = .TRUE.
!               if(xcfinr(kk,ics).lt.10.and.xcfinr(kk,ics).gt.0.1)
!    *             doneexpo(kk) = .TRUE.

                       !if(xrr(kk,nc).gt.0) then
             end if


! SPECIAL CHEMSOLVE DEBUG WRITE - LLEXPO SOLVER
!          if(c_kkw.ge.0. and.
!    *         (c_tchem(ics).eq.'    APIN'.or.
!    *          c_tchem(ics).eq.'    LIMO')        ) then
!            write(c_out,251) rloss(   kk, nc), xrp(   kk,nc),
!    *                                                alpha(   kk)
! 251          format(/,'LLEXPO DEBUG: rloss, xrp, alpha=rl/xrp-1:',/,
!    *         (8(1pe10.3))   )
!            write(c_out,254) rpro (   kk, nc), c_xcin(   kk,ics),
!    *            c_xcemit(   kk,ics),               beta(   kk)
!            write(c_out,*) ic, ics, c_tchem(ic), c_tchem(ics)
!            write(c_out,*) c_iter, doneexpo(kk)
! 254          format(/,'LLEXPO DEBUG: rpro,xcin, xcemit, beta=rt/kt',/,
!    *         (8(1pe10.3))   )
!            write(c_out,256)  xcfinr(   kk,ic)
! 256          format(/,'XCFINR = ', 1pe10.3)
!          end if    !if(   kk.gt.0.)
! END DEBUG WRITE


!          else            !if(xrp  (kk).gt.0) then
                           !if(xrp(kk,nc).gt.0) then
           end if

                     !if(.not.llexpo) then
         end if

!   BACKWARD EULER SOLUTION FOR SINGLE SPECIES
!    The true equation is =RP/(RL/XR); modified to avoid second divide.

!  Use Back-Euler solution if option is selected, or as fallback if expo
!  Note:  ZERO PROTECT above for rloss.

         if(.not.doneexpo(kk)) then
            xrr(kk, nc)= xrp(kk,nc)*rpro(kk,nc)/rloss(kk,nc)
            xcfinr(kk,ics) = 1.

! SPECIAL CHEMSOLVE DEBUG WRITE - LLEXPO SOLVER
!          if(c_kkw.ge.0. and.
!    *         (c_tchem(ics).eq.'    APIN'.or.
!    *          c_tchem(ics).eq.'    LIMO')        ) then
!          write(c_out,271)
! 271        format(/,'BACK-EULER: xrp xcfinr, rpro, rloss')
!          write(c_out,*) c_iter
!          write(c_out,*) c_tchem(ics), doneexpo(kk)
!          write(c_out, 272) xrp(kk,nc), xcfinr(kk,ics),
!    *            rpro(kk,nc), rloss(kk,nc)
! 272        format(8(1pe10.3))
!          end if


                               !if(.not.doneexpo(kk) then
         end if

!                      end do            ! kk vector loop

! TEMPORARY DEBUG ADD 2009
!        if(c_kkw.gt.0                 )
!    &     write(43,*) 'nc, xrr,rpro, rloss=',nc,xrr(kk,nc),
!    &        rpro(kk,nc), rloss(kk,nc)
!        if(c_kkw.gt.0                 )
!    &    write(43,*) 'rpro(1), rpro(2)    =', rpro(kk,1),rpro(kk,2)


!    H2O2 SPECIAL OPTION (for AQUEOUS CO3 NONCONVERGENCE)
!      MAXIMUM H2O2 = PRIOR H2O2 + ODDHSRC
!      TO USE THIS, NEED TO SUM ODDHSRC (sources only) ALONG WITH ODDHSU
!
         if(c_tchem(ics).eq.'    H2O2') then
!          do kk=1,c_kmax      ! kk vector loop
             if(xrr(kk,  nc).gt.oddhsrc(kk,1)+  c_xcin(kk,ics)) then
                xrr(kk, nc)  =oddhsrc(kk,1)+  c_xcin(kk,ics)

! ZERO PROTECT CORRECTION 52004 - cut, should never be zero
!  --> if it  goes below 1e-30 can be zero!!!
!           if(xrr(kk, 1).lt.1.0e-30) xrr(kk,1)=1.0e-30
             end if
! (THIS LINE REPLACED WITH SECTION IMMEDIATELY BELOW.)
!            xrr(kk, nc) =(xrr(kk,nc) **0.70) * (xrp(kk,nc)) **0.30
!          end do       ! kk vector loop
                     !if(c_tchem(ics).eq.'    H2O2')
         end if

!   ***DIFFICULT CONVERGENCE OPTION***
!      GEOMETRIC MEAN (0.7 or 0.5) IF FLAGGED.
!
!   CONVERGENCE OPTION (June 2009): geom avg for first 1-3 iterations
!                                  (but not for  NO3)   ==>NOT USED.
!             (test with fort.87cohc3, cohc_u, rb_hg_rpai)
!             (note: lself correction above is necessary)

!   FLAG FOR:  H2O2   and SELF-REACTION
!   (Self-reaction flag for SO5- +SO5- as well as H2O2).
!
!   If CO3, H2O2 here - slow convergence. Else, CO3-H2O2 small oscillati
!     (changed:  CO3 linked to Hx. H2O2 remains here)

! temporary debug write
!        if(c_kkw.gt.0.and.(ics.eq.5.or.ics.eq.4))
!    &        write(43,*) "ics tchem, xr =", ics, c_tchem(ics)
!    &         , xrr(c_kkw,nc), lself

! SPECIAL FIX FOR NO3, N2O5:  set lself=F;  these must not be solved
!    with geometric avg - messes up NOx
!
!
           if(c_tchem(ics).eq.'     NO3'                                &
     &        .or.c_tchem(ics).eq.'    N2O5' ) lself = .FALSE.

! CONVERGENCE OPTION - ADD THIS CONTROL if geom avg used for 1st iters
                                                   ! geom avg
         if( (c_iter.gt.1.or..not.c_lsts(ics) )                         &
     &     .and.c_tchem(ics).ne.'     NO3'                              &
     &     .and.c_tchem(ics).ne.'    N2O5'                              &
     &                                          ) then

           if( (lself)                                                  &
     &      .or. c_tchem(ics).eq.'    H2O2'                             &
     &                                            ) then
! 2009 CONVERGENCE OPTIONS  (best: c_iter.le.1 or skip)
!              (if this is used, also add if control just above and endi
!    &      .or.(c_iter.le.1                            )
!    &      .or.(c_iter.le.1.and.c_icat(ncsol(1)).le.8)
!    &      .or.(c_iter.le.3.and..not.c_lsts(ics)       )

                                               ! always include

! FAILED OPTIONS
!    *      .or. c_tchem(ics).eq.'     CLG'    !  fails
!    *      .or. c_tchem(ics).eq.'    HCLG'
!    *      .or. c_tchem(ics).eq.'    HCL2'
!    *      .or. c_tchem(ics).eq.'     CLO'
!    *      .or. c_tchem(ics).eq.'     NO3'    ! fails!! must skip
!    *      .or. c_tchem(ics).eq.'    N2O5'    ! fails
!    *      .or. c_tchem(ics).eq.'     CO3'
!    *      .or. c_tchem(ncsol(1)).eq.'    HBRG'

!            do kk=1,c_kmax      ! kk vector loop
!               xrr(kk, nc) =(xrr(kk,nc) **0.85) * (xrp(kk,nc)) **0.15
!               xrr(kk, nc) =(xrr(kk,nc) **0.70) * (xrp(kk,nc)) **0.30
                xrr(kk, nc) =(xrr(kk,nc) **0.50) * (xrp(kk,nc)) **0.50
!            end do        ! kk vector loop

                       ! lself
           end if
                      ! geom. avg
         end if


! DIFFICULT CONVERGENCE OPTION:  SETGEO IF FLAGGED
!   FLAG FOR H2O2 - EITHER ABOVE (AUTOMATIC) OR HERE
!   FAILS

!        if(c_tchem(ics).eq.'    xxxx'
!    *                                            ) then
!          if(c_iter.ge.4) then
!            call setgeom(ics)
!          end if               !if(c_iter.ge.4) then
!          do kk=1, c_kmax          ! kk vector loop
!             xrr(kk, nc) =(xrr(kk,nc) **geomavg(kk,ics))
!    *                     * (xrp(kk,nc)) **(1.-geomavg(kk,ics))
!             history(kk,ics,c_iter) = xrr(kk,nc)
!          end do                  ! kk vector loop
!        end if              !if(c_tchem(ics).eq.'    H2O2'

! DIFFICULT CONVERGENCE OPTION:   (ADD 30905)
!  PROTECT AGAINST WILD OSCILLATION OF HNO3 FOR FIRST FEW ITERS
!  (For NO3->HNO3->NOx error with high BR)
!  (HNO3 icat 16;  may also use for all slow species icat=1)

         if(c_iter.le.3.and.c_icat(ics).eq.16) then
!        if(c_iter.le.3.and.(c_icat(ics.eq.1.or.c_icat(ics).eq.16)) then
!          do kk=1, c_kmax          ! kk vector loop
              if(xrr(kk, nc).gt.5.*xrp(kk,nc))                          &
     &             xrr(kk, nc) =  5.*xrp(kk,nc)
              if(xrr(kk, nc).lt.0.2*xrp(kk,nc))                         &
     &             xrr(kk, nc) = 0.2*xrp(kk,nc)
!          end do                  ! kk vector loop
                           !if(c_iter.le.3.and.c_icat(ics).eq.16) then
         end if

!   REGULAR DEBUG WRITE
!        if(c_kkw.gt.0                 )
!    *        write(c_out,101) c_tchem(ics), ics,xrr(c_kkw, nc) ,
!    *   xrp(c_kkw,nc) ,rpro(c_kkw,nc), rloss(c_kkw,nc)
!        if(c_kkw.gt.0.and.lself) write(c_out,*) 'lself =', lself
! 101    format(' CHEMSOLVE (PAIRED SPECIES):  IC  XR  XRP  RPRO  RLOSS'
!    *      ,/,a8,2x,i5,(8(1pe10.3)))
!   TEMPORARY ADDITION
!        if(c_kkw.gt.0                 )
!    &      write(c_kkw,*)'   (xrr=xrp*rpro/rloss)'
!        if(c_kkw.gt.0                 )
!    &    write(43,*) 'rpro(1), rpro(2)    =', rpro(kk,1),rpro(kk,2)


!   ADD SOLUTION TO PAIR SUM FOR PAIR GROUP
         if(nsolv.ge.3.and.nssolv(nsolv).eq.1) then
!          do kk=1,c_kmax          ! kk vector loop
             xrrpair(kk) = xrrpair(kk) + xrr(kk,nc)                     &
     &                                      * c_pairfac(ics)
!          end do                 ! kk vector loop

                        !if(nsolv.ge.3.and.nssolv(nsolv).eq.1) then
         end if

!   SUM XRRM FOR NORMALIZATION FOR MULTISOLVE
!
         if(nsol.gt.1                       ) then
!          do kk=1,c_kmax      ! kk vector loop
!            xrm(kk,is) =  xrm(kk,is) + xrp(kk,nc)*c_pairfac(ics) ! OLD
             xrrm(kk,is) = xrrm(kk,is) + xrr(kk,nc)
!          end do           ! kk vector loop
                        !if(nsol.gt.1                       ) then
         end if
!
!    RESET XRR (TOTAL SPECIES SOLUTION) EQUAL TO NEW/OLD RATIO
!        do kk=1,c_kmax      ! kk vector loop
!          xrm(kk,is) = xrm(kk,is) + xrp(kk,nc)        ! original
!          xrrm(kk,is) = xrrm(kk,is) + xrr(kk,nc)        ! original
           xrr(kk,nc) = xrr(kk,nc)  /xrp(kk, nc)
!        end do           ! kk vector loop
!
!   PARTITION THE TOTAL SPECIES BETWEEN GAS-MASTER AND AQUEOUS
!    USING THE SAME GAS-AQUEOUS RATIOS AS PRIOR.

!    ALL CONCENTRATIONS (GAS AND AQUEOUS) ARE UPDATED BY THE RATIO XR/XR
!     (PRIOR TIME STEP, XRIT, PRESERVED HERE)

         do  neq=1,(c_nequil(ics)+1)
           ic=ics
           if(neq.gt.1) ic = c_ncequil(ics,(neq-1))
!  TEST WRITE - GAS/AQUEOUS
! c          if(c_kkw.gt.0.and.c_tchem(ics).eq.'     CO3')
!          if(c_kkw.gt.0                         )
!    *        write(c_out,  131) c_tchem(ic), xc(1,ic),xrp(1,nc)
! 131        format(' CO3 AQUEOUS TEST.  PRIOR/POST XR XRP=',2x,a8,
!          if(c_kkw.gt.0                         )
!    *        write(c_out,  131) c_tchem(ic), xc(1,ic),xrp(1,nc)
! 131        format(' CO3 AQUEOUS TEST.  PRIOR/POST XR XRP=',2x,a8,
!    *             2(1pe10.3))
!

!          do kk=1,c_kmax      ! kk vector loop
              xc(kk,ic) = xc(kk,ic) *xrr(kk,nc)
              c_xcout(kk,ic) = c_xcout(kk,ic)
!          end do        ! kk vector loop

!  TEST WRITE - GAS/AQUEOUS
! c        if(c_kkw.gt.0.and.c_tchem(ncsol(1)).eq.'     CO3')
!          if(c_kkw.gt.0                         )
!    *       write(c_out,  131) c_tchem(ic), xc(1,ic),xc(1,ncsol(1))

!   TEMPORARY DEBUG WRITE
!        if(c_kkw.gt.0                 )
!    &    write(43,*) ' nc,ic,reset xrr, xrp, xc within neq loop:'
!        if(c_kkw.gt.0                 )
!    &    write(43,*) nc,ic, xrr(kk,nc),xrp(kk,nc), xc(kk,ic)


                ! do  neq=1,(c_nequil(ics)+1)
         end do

!   END - PARTITION BETWEEN GAS AND AQUEOUS

!   UPDATE RLOSS, CPRO, AND XRP BASED ON NEW SPECIES CONCENTRATION
!    AND ADD UPDATED CPRO TO RPRO FOR PRODUCTION TO PAIRED SUBSPECIES
!
!    (updated CPRO only used here for sub-species;
!       since primary species formula assumes original CPRO, XRP
!       but update done for all CPRO, to be consistent with updated XRP.
!     Updated RLOSS, CPRO, XRP will be used in MULTISOLVE.)

! TEMPORARY DEBUG WRITE
!        if(c_kkw.gt.0                 )
!    &    write(43,*) 'rpro(1), rpro(2) before update rloss   =',
!    &         rpro(kk,1),rpro(kk,2)

!  UPDATE RLOSS, XRP
!        do kk=1,c_kmax      ! kk vector loop
           rloss(kk,nc) = rloss(kk,nc) * xrr(kk,nc)
           xrp(kk,nc) = xrp(kk,nc) * xrr(kk,nc)
!        end do          !kk vector loop
!
! UPDATE CPRO
         do ncc=1,nsolv
!          do kk=1,c_kmax      ! kk vector loop
              cpro(kk,nc,ncc) = cpro(kk,nc,ncc) * xrr(kk,nc)
!          end do          !kk vector loop
                          !do ncc=1,nsolv
         end do
!
! UPDATE RPRO
         if(nsolv.gt.nc) then
           do ncc=(nc+1), nsolv
             if(nssolv(nc).eq.nssolv(ncc)) then
!              do kk=1,c_kmax      ! kk vector loop
                 rpro(kk,ncc) = rpro(kk,ncc) + cpro(kk,nc,ncc)
!              end do               ! kk vector loop
                                !if(nssolv(nc).eq.nssolv(ncc))
             end if
                              !do ncc=(nc+1), nsolv
           end do
                         !if(nsolv.gt.nc)
         end if
!
! GOT HERE - RPRO ABOVE, ADD WRITE?
!
! TEMPORARY DEBUG WRITE
!        if(c_kkw.gt.0                 )
!    &    write(43,*) 'rpro(1), rpro(2) after  update rloss   =',
!    &         rpro(kk,1),rpro(kk,2)


!
!  FUTURE CHANGE - use this instead of UPDATE CPRO, RPRO just above.
! UPDATE CPRO AND RPRO for sub-species only
!        if(nsolv.gt.nc) then
!          do ncc=(nc+1), nsolv
!            if(nssolv(nc).eq.nssolv(ncc)) then
! c              do kk=1,c_kmax      ! kk vector loop
!                cpro(kk,nc,ncc) = cpro(kk,nc,ncc) * xrr(kk,nc)
!                rpro(kk,ncc) = rpro(kk,ncc) + cpro(kk,nc,ncc)
! c              end do               ! kk vector loop
!            end if              !if(nssolv(nc).eq.nssolv(ncc))
!          end do              !do ncc=(nc+1), nsolv
!        end if           !if(nsolv.gt.nc)


                     !nc=1,nssolv
       end do
! ---------
!  END LOOP TO SOLVE SPECIES CONCENTRATIONS- INTERNAL PAIRS
! ---------
! ---------
!  NORMALIZATION:  UPDATE SPECIES FOR PAIR GROUP CONSERVATION OF MASS
!                  OR FOR MULTISOLVE TO PRESERVE ORIGINAL PAIR GROUP SUM
!  OPTION:  UPDATE SPECIES CONCENTRATIONS FOR PAIR GROUP CONSERVATION OF
! ---------
!   PAIR GROUP SUM IS USED ONLY IF PAIR GROUP HAS >3 MEMBERS
!     AND NO MULTISOLVE (since multisolve normalizes from prior )

! FROM THIS VERSION - FUTURE CHANGE (remove normalization in multisolve)
         if(nsolv.ge.3.or.nsol.gt.1         ) then

!  DO FOR ALL PAIR GROUPS
!   Indices:
!     nc=chemsolve species counter number
!     is = chemsolve group number
!     icpair = pair group lead species
!     ics = this species of pair group.
!      (This loop is equivalent to:
!           nc = 1, nsolv;   ics = ncsolv(nc) )

           do is=1,nsol
!            icc=ncsol(is)
!            icpair=ncsol(is)
             icpair = c_nppair(ncsol(is),2)

!     MULTISOLVE NORMALIZATION FACTOR:  XRM/XRRM
!       (note, XRM different from XRPAIR:  XRPAIR includes PAIRFAC)
!
             if(nsol.gt.1) then
!              do kk=1,c_kmax      ! kk vector loop
                 alpha(kk) = 1.

                 if(xrrm(kk,is).gt.0) then
                   alpha(kk) = xrm(kk,is)/xrrm(kk,is)
                                  !if(xrrm(kk,is).gt.0) then
                 end if

!              end do             ! kk vector loop

!     PAIR GROUP NORMALIZATION FACTOR:
!        Group sum = RP/RL.  Adj*XRR = XRP*RP/RL, Adj=(XRP/XRR)*(RP/RL)
!
                               !if(nsol.gt.1) then
             else
!              do kk=1,c_kmax      ! kk vector loop
                 alpha(kk) = 1.
                 if(rlpair(kk,icpair).gt.0.and.xrrpair(kk).gt.0) then
                    alpha(kk) =   (xrppair(kk)/xrrpair(kk))             &
     &               * (rppair(kk,icpair)/rlpair(kk,icpair))
                              !if(rlpair(kk).gt.0.and.xrrpair(kk).) then
                 end if

! c            end do             ! kk vector loop
                               !if(nsol.gt.1) then
             end if

! DO FOR ALL SPECIES IN PAIR GROUP

             nc=0
             do iss=1,(c_nppair(icpair,3)+1)
               nc=nc+1
               ics = icpair
!              ics = c_nppair(icpair,2)   ! no difference
               if(iss.gt.1) then
                 ics = c_nppair(icpair,iss+2)
               end if
!              icpair = c_nppair(ics,2)    ! should be equal to setting
!
!
! PAIR GROUP NORMALIZATION.
!  PAIR ADJUSTMENT OPTION (2008): - SKIP if XRP=RPRO (zero production)

             do  neq=1,(c_nequil(ics)+1)
               ic=ics
               if(neq.gt.1) ic = c_ncequil(ics,(neq-1))
!                do kk=1,c_kmax      ! kk vector loop

! TEST 2008 OPTION:  skip if XRP=RPRO
                  if(xrp(kk,nc).ne.rpro(kk,nc) ) then
                    xc(kk,ic) = xc(kk,ic) *alpha(kk)
                  end if
! ORIGINAL
!                 xc(kk,ic) = xc(kk,ic) *alpha(kk)

!                end do        ! kk vector loop
                           ! do  neq=1,(c_nequil(ics)+1)
             end do

                                !do i=1,(c_nppair(ic,3)+1)
             end do
! END LOOP - DO FOR ALL SPECIES IN PAIR GROUP

! CHEMSOLVE REGULAR DEBUG WRITE
!          if(c_kkw.gt.0) write(c_out,102) xrrpair(c_kkw)
!    *        , xrppair(c_kkw), rppair(c_kkw,icpair)
!    *         , rlpair(c_kkw,icpair),  alpha(c_kkw)
!    *           ,gamma(c_kkw)
! 102        format(' CHEMSOLVE PAIR ADJUSTMENT: xrrpair xrppair ',
!    *            'rppair  rlpair ADJ. FACTOR:',/,(5(1pe10.3)))

                             !do is=1,nsol
           end do
! END LOOP - DO FOR ALL PAIR GROUPS.

                        !if(nsolv.ge.3.and.nssolv(nsolv).eq.1) then
         end if

! ---------
!  END UPDATE SPECIES CONCENTRATIONS FOR PAIR GROUP SUM CONSERVATION OF
! ---------
! ---------------------------------------------
! END CALCULATE SPECIES CONCENTRATIONS:  INTERNAL PAIRS
! ---------------------------------------------
!
! ---------------------------------------------
! CALCULATE SPECIES CONCENTRATIONS: MULTISOLVE AND NOXSOLVE
! ---------------------------------------------
!
!   The algorithms:
!    MULTISOLVE does a full back-euler matrix inversion
!     using LINSLV/RESOLV to solve for >2 rapidly interacting species
!    It solves for interacting species groups
!     where each group may consist of a pair or pair chain.
!    The groups are identified by input to CHEMSOLV (currently ic1, ic2,
!    MULTISOLVE would preserve the previously calculated ratio
!     among paired species or species pair chains
!     and aqueous equilibria.
!
!    NOXSOLVE is a special solution for O3-NO-NO2
!      based on the rapid exchange O3+NO<->NO2
!      it uses preliminary calculations in CHEMSOLV and then calls NOXSO
!
!   FOR MULTISOLVE/NOX-SOLVE (STANDARD OPTION):
!    PAIR SOLUTION is normalized to keep original within-pair sum unchan
!    NOXSOLVE or MULTISOLVE changes pair sums (preserving internal parti
!     based on interaction between pair groups.
!    (implemented above in INTERNAL PAIRS )
!
! NOTE:  pair group sums were set above in INTERNAL PAIRS
!   xrm = prior pair group sum
!   xrrm = updated pair group sum (not done yet)
!   xrp = updated individual (gas+aq) species sum from PAIR SOLUTION.
!
!  ---------
!  MULTISOLVE CONTROL:  DO ONLY IF MULTISOLVE SPECIES NONZERO
!  ---------
!      if(nssolv(nsolv).gt.1) then
       if(nsol.gt.1         ) then
!
! ---------
! LOOP TO NORMALIZE INTERNAL PAIR SOLUTION FOR NOXSOLVE/MULTISOLVE
! ---------
!  CUT - DONE ABOVE

!  NOTE:  CHEMISTRY PRODUCTION, LOSS SET ABOVE
!   NOT UPDATED AFTER PAIR SOLUTION.

! ---------
!  CALL NOXSOLVE
! ---------
! NOXSOLVE solves for (O3, NO2, NO) in that order
!    using O3+NO<->NO2 - Ox and NOx, and counted sourcnx, sourcox, etc.
!    O3, NO2, etc. can also be part of a pair (for O3<->O1D)
! Solution is returned as XRRM(KK,IS)
!

!  (NOXSOLVE OPTION - EITHER CALL NOXSOLVE OR USE MULTISOLVE HERE.
!    IF MULTISOLVE, CONVERGENCE IS SLOWER AND MORE DIFFICULT)
!
         if (ncsol(1).eq.c_no3      .and.ncsol(2).eq.c_nno2) then

!        if(c_iter.eq.-1) then    ! ALT TO ELIMINATE

             call noxsolve(ncsol(1),ncsol(2),ncsol(3))

! CONVERT SOLUTION INTO NEW/OLD RATIO (XRRM/XRM)
           do is=1,nsol
!            do kk=1,c_kmax      ! kk vector loop
               xrrm(kk,is) = xrrm(kk,is)  / xrm(kk, is)
!            end do             ! kk vector loop
                             !do is=1,nsol
           end do

                          !if(c_tchem(ncsol(1)).eq.    '  O3'.and
         else
!
!  ---------
!  SET UP AND CALL MULTISOLVE
!  ---------
!   FUTURE DO:
!      Control to replace MULTISOLVE with simple solution if CPM=0.
!      Possible:  call RESOLV for easy convergence -
!        must then save and replace reduced AX, IPA.
!
!   ENTER VECTOR AND MATRIX FOR AX=B BACK-EULER SOLUTION
!       Equation:  Xi = Xio + Pi(X)-Li(X) = Xio +Pi(Xp)-Li(Xp) +dRi/dxj
!                  Xi-Xip= (Xio + Pi(Xp)) - (Xip + Li(Xp)) + d(P-L)/dxj
!                 (I-dR/dxj)(Xj-Xjp) = ((Xio + Pi(Xp)) - (Xip + Li(Xp))
!               [Xjp - (dR/dxj)*Xjp][Xj/Xjp-1] = (Xio + Pi(Xp)) - (Xip +
!                      AX     *    XX          =   BX
!       XX = xrrm - 1
!       BX = rpm - rlm
!       AA(i,i) = rlm
!       AA(i,j) = -cpm(j,i) for j.ne.i


!  VECTOR LOOP - solution is not vectorized
!        do kk=1,c_kmax                 ! kk vector loop

!  SET ARRAY
           do is=1,nsol
            BX(is) = rpm(kk,is) - rlm(kk,is)
            do iss=1,nsol
              AX(is,iss) = 0. - cpm(kk,iss,is)
                                  !do iss=1,nsol
            end do
            AX(is,is) = rlm(kk,is)
                                !do is=1,nsol
           end do

! TEMPORARY MULTISOLVE DEBUG WRITE  ncsol(is)
!         if(c_kkw.gt.0) then
!           do is=1,nsol
!            write(c_out,221) is, c_tchem(ncsol(is))
! 221          format(/'MULTISOLVE: IS, SPECIES = ',i4,2x,a8)
!            write(c_out,222) rpm(c_kkw,is), rlm(c_kkw,is), BX(is)
! 222          format('   RPM RLM BX(=rpm-rlm) = ',5(1pe10.3))
!            write(c_out,223) (cpm(c_kkw,iss,is),iss=1,nsol)
!            write(c_out,223) (AX(is,iss),iss=1,nsol)
! 223          format('  CPM/AX = ', 4(1pe10.3))
!           end do          !do is=1,nsol
!         end if

! CALL MULTISOLVE
           call LINSLV(AX, BX, XX, nsol)

! ENTER RESULT INTO XRRM (ratio adjustment)
! OPTION:  Limit size of change, also protect against zero.
           do is=1,nsol
             xrrm(kk,is) = XX(is) + 1.
             if(xrrm(kk,is).lt.0.001) xrrm(kk,is) = 0.001
                                !do is=1,nsol
           end do

!        end do                        ! kk vector loop
! END  VECTOR LOOP - solution is not vectorized
!
!  MULTISOLVE NORMALIZATION OPTION
!         do kk=1,c_kmax            ! kk vector loop
            gamma(kk) = 0.
            beta(kk) = 0.
!         end do                   ! kk vector loop
          do is=1,nsol
!           ic =ncsol(is)
            ic = c_nppair(ncsol(is),2)
!           do kk=1,c_kmax            ! kk vector loop
              gamma(kk) = gamma(kk) + xrm(kk,is)                        &
     &                  *c_multfac(ic)
               beta(kk) =  beta(kk) + xrm(kk,is)*xrrm(kk,is)            &
     &                  *c_multfac(ic)
!           end do                   ! kk vector loop
                                  !do is=1,nsol
          end do

!         do kk=1,c_kmax      ! kk vector loop
           alpha(kk) = 1.
           if(rlmulti(kk).gt.0.and. beta(kk)  .gt.0) then
              alpha(kk) =   (gamma(kk)  /beta(kk)   )                   &
     &               * (rpmulti(kk)      /rlmulti(kk)      )
                          !if(rlmulti(kk).gt.0.and. beta(kk)  .gt.0) the
           end if
          do is=1,nsol
!           do kk=1,c_kmax            ! kk vector loop
! OPTION HERE
              xrrm(kk,is) = xrrm(kk,is) * alpha(kk)
!           end do                   ! kk vector loop
                                  !do is=1,nsol
          end do

! TEMPORARY MULTISOLVE DEBUG WRITE - MULTISOLVE NORMALIZATION
!         if(c_kkw.gt.0) then
!           write(c_out,226 ) beta(c_kkw), gamma(c_kkw),
!    *       rpmulti(c_kkw), rlmulti(c_kkw), alpha(c_kkw)
! 226        format(/,'MULTISOLVE NORMALIZE: XRR XRP RP RL NORMFAC=',
!    *              /,5(1pe10.3))
!         end if               !if(c_kkw.gt.0) then

! c            end do             ! kk vector loop



                          !if(c_tchem(ncsol(1)).eq.'      O3'.and
         end if
!  ---------
!  END:  CALL NOXSOLVE/MULTISOLVE
!  ---------

!   REGULAR DEBUG WRITE
!        if(c_kkw.gt.0)  then
!          do nc=1, nsolv
!            ics = ncsolv(nc)
!            if(c_nppair(ics,2).eq.ics) then
!              is=nssolv(nc)
!              write(c_out,106) c_tchem(ics), ics,xrrm(c_kkw, is) ,
!    *    xrm(c_kkw,is) , rpm(c_kkw,is),   rlm(c_kkw,is)
! 106    format(' CHEMSOLVE (MULTISOLVE/NOX):  IC  XRR XRP  RPRO  RLOSS'
!    *      ,/,a8,2x,i5,(8(1pe10.3)))
!            end if       !if(c_nppair(ic,2).eq.ic)
!          end do          !do nc=1, nsolv
!        end if         !if(c_kkw.gt.0)   ... end debug write
!
!  -------
!  ENTER NOXSOLVE/MULTISOLVE VALUES FOR PAIRS AND GAS/AQUEOUS
!  -------
!  Enter for all paired species; partition among gas/aqueous
         do nc = 1, nsolv
           is=nssolv(nc)
           ics = ncsolv(nc)

!   UPDATE EACH PAIR SPECIES AND GAS/AQUEOUS SPECIES BY THE RATIO XRM/XR
!    (This preserves prior partitioning among pair species and gas/aqueo

           do  neq=1,(c_nequil(ics)+1)
             ic=ics
             if(neq.gt.1) ic = c_ncequil(ics,(neq-1))

!            do kk=1,c_kmax      ! kk vector loop
               xc(kk,ic) = xc(kk,ic) *xrrm(kk,is)
!            end do        ! kk vector loop

                  ! do  neq=1,(c_nequil(ics)+1)
           end do

!   END - PARTITION BETWEEN GAS AND AQUEOUS

                    !do nc = 1, nsolv
         end do
!  -------
!  END - ENTER NOXSOLVE/MULTISOLVE VALUES INTO PAIRS AND GAS/AQUEOUS
!  -------

                         !if(nsol.gt.1)  (nssolv(nsolv).gt.1)
       end if
!  ---------
!  END MULTISOLVE CONTROL
!  ---------
!
! ---------------------------------------------
! END - CALCULATE SPECIES CONCENTRATIONS: MULTISOLVE AND NOXSOLVE
! ---------------------------------------------
!
! ---------------------------------------------
! CALCULATE CHEMICAL PRODUCTION AND LOSSES FOR DOWN-CASCADE SPECIES.
! ---------------------------------------------
!
!  *** END IF-LOOP -1 TO SKIP LOSS AND XR CALC FOR SLOW-SPECIES 'PRE'.
!          (END OF ONESOLVE  'POST' LOOP)
!  CUT JANUARY 2005
!             end if               ! if(ic2.ne.-1.and.ic2.ne.-3) then

!  *** IF-LOOP -2 TO SKIP DOWN-CASCADE CALC. FOR SLOW-SPECIES 'POST'.
!         (LOOP EXECUTED FOR full ONESOLVE AND FOR 'PRE')
!  CUT JANUARY 2005
!             if(ic2.ne.-2) then
!  ***
!

!  LOOP TO CALCULATE DOWN-CASCADE PRODUCTION
!  LOOP TO  RECORD RRP, RRL AND ZERO RP, RL.

!   Note:  brpro adds losses, cross-production to RP, RL (for record).
!   Subsequent down-cascade production will be include in next iteration

       do nc=1, nsolv
         ics = ncsolv(nc)

         if(c_nnrchem(ics).gt.0) then
           do i=1,c_nnrchem(ics)
             nr =  c_nrchem(ics,i)
             call brpro(nr)
                        !do i=1,c_nnrchem(ics)
           end do
                      !if(c_nnrchem(ics).gt.0)
         end if
                    !do nc=1,nsolv
       end do

! LOOP TO CALL EXCORR
!  EXCORR adjusts down-cascade RP, RL, PRONOX and  ODD-H SENSITIVITY
!    for back-forth exchange reactions.
!
!  This avoids bad solution when down-cascade summed RP, RL are dominate
!    by  a rapid back-forth reaction (MCO3<->PAN, HNO4<->NO2+HO2)
!
!  The exchange reaction impact would be exaggerated down-cascade
!    by a straight solution, the down-cascade solution would not
!    account for rapid back-forth exchange
!      (= negative feedback for changed rates)
!
!  To avoid this, down-cascade RP, RL, PRONOX and ODD-H SENSITIVITY
!   are reduced by an amount that reflects back-forth  response to
!   change in rates.  Effective RP, RL is  reduced by linked back-reacti
!
!
       do nc=1, nsolv
         ics = ncsolv(nc)
         if(c_exspec(ics,1).ne.0) call excorr(ics)

                    !do nc=1,nsolv
       end do
!

!  LOOP TO  RECORD RP, RL
!  NOTE:  RRP, RRL represent running sum through cascade.
!         RP, RL represent final sum through cascade.
!  ALSO- these are used in AQUASOLVE.
!
! OPTION:  SUM GAS+AQUEOUS RP, RL INTO GAS-ONLY RP, RL?
!   no, this may mess up AQUASOLVE.
!
! OPTION:  THIS CAN BE MOVED ABOVE EXCORR
!    so that it preserves full RP, RL for exchanged species
!    (but may not record back-forth for  down-cascade)

       do nc=1, nsolv
         ics = ncsolv(nc)
         do  neq=1,(c_nequil(ics)+1)
           ic=ics
           if(neq.gt.1) then
             ic = c_ncequil(ics,neq-1)
!
! OPTION: RECORD SUM OF GAS+AQUEOUS PRODUCTION IN GAS-MASTER
!            c_rp(kk,ics) = c_rp(kk,ics) + rrp(kk,ic)
!            c_rl(kk,ics) = c_rl(kk,ics) + rrl(kk,ic)
!
                            !if(neq.gt.1) then
           end if

!          do kk=1,c_kmax          ! kk vector loop
             c_rp(kk, ic) = rrp(kk,ic)
             c_rl(kk,ic) = rrl(kk,ic)
!          end do                 ! kk vector loop

                       !do  neq=1,(c_nequil(ics)+1)
         end do
                    !do nc=1,nsolv
       end do

!  LOOP TO ZERO RRP, RRL
!   ZERO RRP HERE so that running sum for next iteration includes
!           down-cascade production.

       do nc=1, nsolv
         ics = ncsolv(nc)
         icpair = c_nppair(ics,2)
         rppair(kk,icpair) = 0.
         rlpair(kk,icpair) = 0.
         do  neq=1,(c_nequil(ics)+1)
           ic=ics
           if(neq.gt.1) then
             ic = c_ncequil(ics,neq-1)
           end if

           rrp(kk,ic) = 0.
           rrl(kk,ic) = 0.

                       !do  neq=1,(c_nequil(ics)+1)
         end do
                    !do nc=1,nsolv
       end do
!
!  *** END IF-LOOP -2 TO SKIP DOWN-CASCADE CALC FOR SLOW SPECIES 'POST'.
!        (END OF LOOP FOR full ONESOLVE AND 'PRE')
!  CUT JAUNARY 2005
!             end if                  ! if(ic2.ne.-2) then
!  ***
!
! CHEMSOLVE DEBUG WRITE
!       if(c_kkw.gt.0) write(c_out,*) '---END CHEMSOLVE--'
!
!
! ----------------------------------------------------------------
! END CHEMSOLVE.
! ----------------------------------------------------------------

! END CHEMSOLVE
 2000 return
      END
! -------------------------------------------

! CHEMSOLVE ENDS HERE
!

!
!


      subroutine brreac(nr)

! BRREAC CALCULATES REACTION RATE FOR THE SPECIFIED REACTION
! AND STORES IT IN RR().
! FOR AQUEOUS REACTIONS, IT CALCULATES RR IN GAS UNITS.
! CALLED BY CHEMSOLVE, NOXSOLVE, EXCORR, etc.
!
! Input:  nr  (reaction number)
! Output:  c_rr (rate of reaction, molec/cm3/step)
!
! Called by:
!     chemsolve
!     noxsolve
!     excorr
!
! Calls to:  none.
!
! ---------------------------------------------
! History:
!  12/06 Written by Sandy Sillman from boxchemv7.f
!
! -------------------------------------------------------------------

! ----------------------------------------
      implicit none

      kk=1

! NOTE - ASSUME THAT ICR1>0 THROUGHOUT.
      icr1 = c_reactant(nr,1)
      icr2 = c_reactant(nr,2)
!     if(icr1.le.0) return

!  CALCULATE REACTION RATE.
!     do 15211 kk=1,c_kmax
        c_rr(kk,nr) = c_time*ratek(kk,nr)*xc(kk,icr1)
15211 continue

      if(icr2.gt.0) then
!       do 15214 kk=1,c_kmax
         c_rr(kk,nr) = c_rr(kk,nr) * xc(kk,icr2)
15214   continue
      end if

!  CONVERT AQUEOUS REACTIONS TO GAS UNITS
!    AQUEOUS REACTION IS IDENTIFIED BY REACTANT NUMBER
!       DIFFERENT FROM ITS GAS-MASTER SPECIES.
      if(icr1.ne.c_npequil(icr1)) then
!       do 15216 kk=1,c_kmax
         c_rr(kk,nr) = c_rr(kk,nr)*c_h2oliq(kk)*avogadrl
15216   continue
      end if


! END BRREAC

 2000 return
      END
! ----------------------------------------



      subroutine brpro(nr)
!
! This calculates reaction rates (RR),
!  and adds to species production (RP) and loss (RL)
!  for a given reaction (nr).
!
! It also sums species loss rates (rloss) and radical sums
!   (oddhsum, etc) for the NOx and HOx solution.
!
! It also adjusts pair sums (RPPAIR, RLPAIR)
!
! This is called from chemsolve (solution for individual species)
!  before the calculation of species concentrations,
!  for reactions associated with species production
!
! And is called after the calculation of the species concentration
!  to get the complete sum of species losses and production
!  for all reactants and products of reactions linked to the species.
!
!  (The resulting species production/loss is used in the solution
!    for species concentrations.
!   Note, RP and RL are set to zero when the species concentration
!    is calculated, so that species RP and RL are sums for
!    all reactions over a full cycle of present+past iterations.)
!
! Inputs:  reaction number (nr)
!
! Outputs:  Reaction rate (RR) based on species concentrations;
!           Species production and loss (RP, RL)
!           Chemistry production sums (oddhsum, etc.)
!
! Called by:    chemsolve.
!
! Calls to:  brreac
!
! ---------------------------------------------
! History:
!  12/06 Written by Sandy Sillman from boxchemv7.f
!
! -------------------------------------------------------------------
! ----------------------------------------------------------
      implicit none

      kk=1

! PRELIM:  CALCULATE REACTION RATE  (alt: cut and invoke elsewhere?)
      call brreac(nr)
!
! PAIR INDEX:  IDENTIFY PAIR GROUP OF NON-KEY-SPECIES REACTANT ONLY.
!    REQUIRES TWO REACTANTS, WHERE 1ST REACTANT IS KEY SPECIES (nicreac)
        icpair = 0
          ic1 = c_npequil(c_reactant(nr,1))
          ic2=0
          if(c_reactant(nr,2).gt.0) then
            ic2 = c_npequil(c_reactant(nr,2))
            if(c_nicreac(nr).eq.ic1) then
              if(c_nppair(ic2,2).ne.c_nppair(ic1,2) )                   &
     &                     icpair = c_nppair(ic2,2)
                                 !if(c_nicreac(nr).eq.ic1) then
            end if

! IF 2ND REACTANT IS KEY SPECIES - can't handle, would make adj. below m
!           if(c_nicreac(nr).eq.ic2) then
!             if(c_nppair(ic2,2).ne.c_nppair(ic1,2) )
!    *             i       icpair = c_nppair(ic1,2)
!           end if                !if(c_nicreac(nr).eq.ic1) then

                               !if(c_reactant(nr,2).gt.0) then
          end if

! ENTER RATE AS LOSS (RL) FOR REACTANTS:

        ic=c_reactant(nr,1)
!       do 15304 kk=1,c_kmax
         rrl(kk,ic) = rrl(kk,ic)+c_rr(kk,nr)
15304   continue

! TEMPORARY BRPRO DEBUG WRITE
!       if(c_kkw.gt.0) write(c_out, 511) c_tchem(ic),  xc(c_kkw,ic),
!    *        rrl(c_kkw,ic), c_rr(c_kkw,nr)
! 511     format('BRPRO: IC XR RRL RR=  ',a8,2x,3(1pe10.3))

        ic=c_reactant(nr,2)
        if(ic.gt.0) then
!         do 15307 kk=1,c_kmax
           rrl(kk,ic) = rrl(kk,ic)+c_rr(kk,nr)
15307     continue

! TEMPORARY BRPRO DEBUG WRITE
!       if(c_kkw.gt.0) write(c_out, 511) c_tchem(ic), xc(c_kkw,ic),
!    *     rrl(c_kkw,ic), c_rr(c_kkw,nr)

        end if

! ENTER RATE AS PRODUCT (RP) FOR PRODUCTS.
! NOTE:  ASSUME IC>0 FOR PRODUCTS IDENTIFIED BY NNPRO.

      if(c_nnpro(nr).gt.0) then
        do 120 n=1,c_nnpro(nr)
         ic = c_product(nr,n)
!          do 15317 kk=1,c_kmax
            rrp(kk,ic) = rrp(kk,ic) + c_rr(kk,nr)*c_stoich(nr,n)
15317      continue

! TEMPORARY BRPRO DEBUG WRITE
!       if(c_kkw.gt.0) write(c_out, 512) c_tchem(ic),
!    *                           rrp(c_kkw,ic), c_rr(kk,nr)
! 512     format('BRPRO: IC RRP RR=  ',a8,2x,3(1pe10.3))

! OPTION - IF PRODUCT EQUALS REACTANT, SUBTRACT FROM RP AND RL
! (This is important for OHL and CLOH in new representation
!  of reaction CL-+OHL=>CLOH (+OHL)
!
! ( Prior:  This only matters for R1O2+R2O2->R1O2+products.
! Reaction is entered twice, once for R1O2 products, once for R2O2.
! So RR is entered as R1O2 loss and product - possible error.
!  For all other reactions, STOILOSS would correct.
!  Since it converges anyway, no problem.
!
           if(ic.eq.c_reactant(nr,1).or.ic.eq.c_reactant(nr,2)) then
             stoicx = c_stoich(nr,n)
             if(stoicx.gt.1) stoicx=1.
!            do 15318 kk=1,c_kmax
              rrl(kk,ic) = rrl(kk,ic) - c_rr(kk,nr)*stoicx
              rrp(kk,ic) = rrp(kk,ic) - c_rr(kk,nr)*stoicx
! 15318        continue

! TEMPORARY DEBUG WRITE
!       if(c_kkw.gt.0) write(c_out, 513) c_tchem(ic),
!    *      rrl(c_kkw,ic),rrp(c_kkw,ic), c_rr(kk,nr)
! 513     format('BRPRO: IC RRL RRP RR=  ',a8,2x,4(1pe10.3))


                  !if(ic.eq.c_reactant(nr,1).or.ic.eq.c_reactant(nr,2))
           else
! END  PRODUCT=REACTANT OPTION.
!   2008 CORRECTION:  - PAIR ADJUSTMENT JUST BELOW IS SKIPPED
!                           IF PRODUCT=REACTANT OPTION IS DONE.
!                    since PRODUCT=REACTANT adjustment does the same thi


! PAIR ADDITION:  FOR DOWN-CASCADE 2nd REACTANT ONLY
!         IF REACTANT AND PRODUCT ARE IN SAME PAIR GROUP,
!            THEN SUBTRACT REDUNDANT PRO/LOSS  FROM RPPAIR, RLPAIR
!            (for same pair group as key species, calc in CHEMSOLVE)
!
!  PAIR INDICES (ic2, icpair) IDENTIFIED ABOVE
!
!    KEY SPECIES IS c_nicreac(nr).
!     PAIR SPECIES IS icpair = c_nppair(c_npequil(ic1), 2)

           if(icpair.gt.0) then
             if(c_nppair(c_npequil(ic),2).eq.icpair) then
               stoicx = c_pairfac(c_npequil(ic)) * c_stoich(nr,n)
               if(stoicx.gt.c_pairfac(ic2)) stoicx = c_pairfac(ic2)
!              do kk=1,c_kmax       ! kk vector loop
                 rppair(kk,icpair) = rppair(kk,icpair)                  &
     &               - c_rr(kk,nr)*stoicx
                 rlpair(kk,icpair) = rlpair(kk,icpair)                  &
     &               - c_rr(kk,nr)*stoicx
!              end do              ! kk vector loop

! TEMPORARY DEBUG WRITE
!              if(c_kkw.gt.0) then
!                 write(c_out, 514) c_tchem(icpair),
!    *           c_tchem(ic), stoicx,
!    *           rppair(c_kkw,icpair), rlpair(c_kkw,icpair),
!    *           c_rr(kk,nr)
! 514     format('BRPRO: SUBTRACT DOWN-CASCADE PAIR PRO/LOSS.',
!    *            ' IC, ICPAIR=',
!    *           2x,a8,2x,a8,/,
!    *           '  STOICX RPPAIR RLPAIR RR=',(4(1pe10.3)))
!              end if

                          !if(c_nppair(c_npequil(ic),2).eq.icpair) then
             end if
                              !if(icpair.gt.0) then
           end if
! END PAIR ADDITION FOR PRODUCT=REACTANT PAIRS

                  !if(ic.eq.c_reactant(nr,1).or.ic.eq.c_reactant(nr,2))
           end if
! END PRODUCT=REACTION OPTION CONTROL,
!                  which includes PAIR ADJUSTMENT (2008 CORRECTION)

!

! END LOOP TO ENTER RATE AS PRODUCT (RP)
  120   continue
      end if

! SUM ODD-H NET AND ODD NITROGEN PRODUCTION (ONLY)
! INCLUDES IDENTIFICATION AND SUM OF dHX/DOH FOR THE REACTION.

! (SENSHX CALC MUST BE IN ITERATIVE LOOP - SENHCAT CHANGES.)

!      do 15321 kk=1,c_kmax
        senshx(kk,1) = 0.
        senshx(kk,2) = 0.
15321  continue

       do 125 n=1,2
        ic = c_reactant(nr,n)
        if(ic.gt.0) then
          ic=c_npequil(ic)
          if(c_icat(ic).gt.0) then
! kvec     do kk=1, kmax   ! kk vector loop
            senshx(kk,1) = senshx(kk,1) + senhcat(kk, c_icat(ic))
! kvec     end do           ! kk vector loop
           if(c_icat(ic).ne.3) then
! kvec       do kk=1, kmax   ! kk vector loop
              senshx(kk,2) = senshx(kk,2) + senhcat(kk, c_icat(ic))
! kvec       end do           ! kk vector loop
           end if
          end if
        end if
  125  continue

! OPTION: double sensitivity for PARAMETERIZED RO2-RO2 reactions
       if(c_nrk(nr).eq.-13) then
! kvec     do kk=1, kmax   ! kk vector loop
            senshx(kk,1) = 2.*senshx(kk,1)
! kvec     end do           ! kk vector loop
      end if

       do i=1,2

! kvec  do kk=1,c_kmax   ! kk vector loop
          oddhsum(kk,i) = oddhsum(kk,i) + c_rr(kk,nr)*c_oddhx(nr,i)
          oddhdel(kk,i) = oddhdel(kk,i) + c_rr(kk,nr)*c_oddhx(nr,i)     &
     &     *senshx(kk,i)
! kvec  end do             ! kk vector loop

         if(c_oddhx(nr,i).gt.0) then
! kvec    do kk=1,c_kmax   ! kk vector loop
            oddhsrc(kk,i) = oddhsrc(kk,i) + c_rr(kk,nr)*c_oddhx(nr,i)
! kvec    end do             ! kk vector loop
         end if

         if(ic1.eq.c_noh      ) then
! kvec    do kk=1,c_kmax   ! kk vector loop
             oddhloh(kk,i) = oddhloh(kk,i) - c_rr(kk,nr)*c_oddhx(nr,i)
! kvec    end do            ! kk vector loop
!    &       nr,i,c_oddhx(nr,i), (c_treac(nrx,nr),nrx=1,5)
                                    !if(c_tchem(ic1).eq.'      OH') then
         end if

! TEMPORARY DEBUG WRITE - IN  LOOP ABOVE
!         if (c_oddhx(nr,i).gt.0)
!    &      write (43,*) 'ERROR: NR,I,oddhx=',


         if(ic1.eq.c_nho2     ) then
! kvec    do kk=1,c_kmax   ! kk vector loop
           oddhlho2(kk,i) = oddhlho2(kk,i) - c_rr(kk,nr)*c_oddhx(nr,i)
! kvec    end do             ! kk vector loop
                                    !if(c_tchem(ic1).eq.'     HO2') then
         end if

         if(ic2.gt.0) then
           if(ic2.eq.c_noh      ) then
! kvec       do kk=1,c_kmax   ! kk vector loop
               oddhloh(kk,i) = oddhloh(kk,i) - c_rr(kk,nr)*c_oddhx(nr,i)
! kvec       end do             ! kk vector loop
                                      !if(c_tchem(ic2).eq.'      OH') th
           end if

           if(ic2.eq.c_nho2     ) then
! kvec      do kk=1,c_kmax   ! kk vector loop
             oddhlho2(kk,i) = oddhlho2(kk,i) - c_rr(kk,nr)*c_oddhx(nr,i)
! kvec      end do             ! kk vector loop
                                      !if(c_tchem(ic2).eq.'     HO2') th
           end if
                                   !if(ic2.gt.0) then
         end if

                !do i=1,2
       end do
!

       if(c_pronox(nr).gt.0) then
!        do 15324 kk=1,c_kmax
          sourcnx(kk) = sourcnx(kk) + c_rr(kk,nr)*c_pronox(nr)
15324    continue
       end if
       if(c_pronox(nr).lt.0) then
!        do 15325 kk=1,c_kmax
           sinknx(kk) =  sinknx(kk) + c_rr(kk,nr)*c_pronox(nr)
15325    continue
       end if

! REGULAR DEBUG WRITE BRPRO
!  (2004: 1pE10.3, f8.2 causes bug in written output.  Fixed.)

!      if(c_kkw.gt.0) write(c_out,15331) nr, (c_treac(nrx,nr),nrx=1,5),
!    *                          c_rr(c_kkw,nr)
!      if(c_kkw.gt.0) write(c_out,15332)
!    *   c_oddhx(nr,1), senshx(c_kkw,1),c_pronox(nr), oddhsum(c_kkw,1),
!    *   oddhdel(c_kkw,1), sourcnx(c_kkw), sinknx(c_kkw)
!    *   ,rrp(c_kkw,9),rrl(c_kkw,9)
!    *   ,rrp(c_kkw,10),rrl(c_kkw,10)
!    *   ,rrp(c_kkw,11),rrl(c_kkw,11)
!      if(c_kkw.gt.0) write(c_out,15332)
!    *   c_oddhx(nr,2), senshx(c_kkw,2),c_pronox(nr), oddhsum(c_kkw,2),
!    *   oddhdel(c_kkw,2)
! 15331  format(/,' BRPRO:  NR   RR  ',i5,2x,a8,'+',a8,
!    *     '->',a8,'+',a8,'+',a8,2x,(1pe10.3) )
! 15332  format(
!    *  '  ODDHXFAC SENSHX PRONOX   ODDHSUM  ODDHDEL SOURCNX SINKNX',
!    *  ' RP9 RL9,10,11',/, 2f8.2,5(1pe10.3),/(8(1pe10.3)))



! END BRPRO
 2000 return
      END
! ----------------------------------------




       subroutine excorr(ic1)

! EXCORR IS A CORRECTION FOR "EXCHANGE" (BACK-FORTH) REACTIONS
! (e.g. PAN<->MCO3, HNO4<->HO2, etc.)
! It goes through the back-forth reactions (expro, exloss)
! associated with the exchange species and "undoes" part of them.
!
! For a SINGLE exchange species (eg HNO4<->NOx, Hx)
! it undoes all except NET FORWARD or BACKWARD.
! 1998 CHANGE:  it undoes based on species lifetime.

! For TWO LINKED SPECIES (PAN-MCO3) it calculates allowable
!  back-forth from PRIOR PAN->MCO3->PAN, and prior MCO3->PAN->MCO3
!  and undoes the rest.
!
! NOTE: SOLUTION FOR TWO LINKED SPECIES is possible
!  only if species are solved simultaneously in same reaction pair
!  or (FUTURE DO) in MULTISOLVE.
!  The 2nd species is identified by EXSPEC - set in QUADINIT.
!
! The UNDO part undoes all RP, RL for down-cascade species,
! including ODDNSUM and ODDHDEL.
!  (But not ODDHSUM, that is unaffected by back-forth exchange.)
!
!  UPDATED FOR AQUEOUS TWOSOLVE.  WATCH OUT FOR PAN, CLOH.
!
!  2005 CHANGE (OPTION):  updates loss (rrl) for exchanged species also.
!   normally, excorr comes after species is solved for, so no matter
!   but it screws up when down-cascade species
!    (e.g. HG3A <=>HG# + SO3- special equilibrium)
!
! Inputs:  species number (ic1) for either individual species
!            or 1st of species pair.
!          Rate of reactions (RR), species production and loss (RP, RL)
!
! Outputs:  Updated RP, RL for subsequent products
!             from back-forth exchange reactions;
!             also updated sums (ODDHDEL)
!
! Called by:    chemsolve (after species solution)
!
! Calls to:  None.
!
! ---------------------------------------------
! History:
!  12/06 Written by Sandy Sillman from boxchemv7.f
!
! -------------------------------------------------------------------
!
! --------------------------
      implicit none

! LOCAL VARIABLES
!
!  ratex(kk)  Rate of back-forth exchange reactions (molec/cm3/timestep)
!              Summed for all exchange reactions affecting species.
!              Equal to minimum of forward and backward rates
!              (more complex for paired species)
!             Preliminary value, used to set 'undo'.
!
! undo (kk)  Rate of back-forth exchange reaction to be 'undone'
!              Adjusted for each  indiv. reactc_ion(molec/cm3/timestep)
!
                                      ! Exchange reaction sum  mol/cm3
      double precision ratex(c_kvec)
                                      ! Exchange undo rate mol/cm3
      double precision undo(c_kvec)
                                      ! Index for number of ex vars
      integer nex

! --------------------------
      kk=1
!
      if(ic1.eq.0) return

!     if(c_expro(ic1,1).le.0.or.c_exloss(ic1,1).le.0) return
      if(c_exspec(ic1,1).eq.0) return

! MAIN LOOP FOR MULTIPLE EXCHANGED SPECIES
!   Exchange reactions are possible with different species partners.
!   Sum up all exchange reactions with the same species
!          and solve  simultaneously

                       ! MAIN LOOP 1000
      do nex=1,20
        if(c_exspec(ic1,nex).eq.0) return
        icx = c_exspec(ic1,nex)

! ZERO
!       do kk=1,c_kmax            ! kk vector loop
          cpro(kk,1,2) = 0.
          cpro(kk,2,1) = 0.
          ratex(kk)  = 0.
          prior(kk)    = 0.
!       end do                   ! kk vector loop
!
! EXCORR DEBUG WRITE
!       if(c_kkw.gt.0) write (c_out,611) c_tchem(ic1)
! 611     format (/,' BEGIN EXCORR:  IC1 (ICX) = ', a8,2x,a8)
!       if(c_kkw.gt.0.and.icx.gt.0) then
!          write(c_out,611) c_tchem(ic1), c_tchem(icx)
!       end if

! SUM EXCHANGE REACTIONS  AS CPRO
!    (multiple reactions are allowed for single exchange)

        do  ii=1,5
          nr = c_exloss(ic1,nex,ii)
          if(nr.gt.0) then
!           do kk=1,c_kmax           ! kk vector loop
              cpro(kk,1,2) = cpro(kk,1,2) +  c_rr(kk,nr)
!           end do                  ! kk vector loop

! EXCORR DEBUG WRITE
!           if(c_kkw.gt.0) write(c_out,614) nr, (c_treac(j,nr),j=1,5),
!    *         c_rr(c_kkw,nr)
! 614         format(' REACTION: ',i4,2x,a8,'+',a8,'=>',a8,'+',a8,'+'
!    *        , a8, ' RR=', 1pe10.3)
!           if(c_kkw.gt.0) write(c_out,615) cpro(kk,1,2), cpro(kk,2,1)
! 615         format ('CROSS PROD 12, 21 = ',2(1pe10.3)  )

                               ! if(nr.gt.0)
          end if
          np = c_expro(ic1,nex,ii)
          if(np.gt.0) then
!           do kk=1,c_kmax           ! kk vector loop
              cpro(kk,2,1) = cpro(kk,2,1) + c_rr(kk,np)
!           end do                  ! kk vector loop

! EXCORR DEBUG WRITE
!           if(c_kkw.gt.0) write(c_out,614) np, (c_treac(j,np),j=1,5),
!    *         c_rr(c_kkw,np)
!           if(c_kkw.gt.0) write(c_out,615) cpro(kk,1,2), cpro(kk,2,1)

                              ! if(np.gt.0)
          end if
                         ! do ii=1,5
        end do

! ESTABLISH RATEX FOR SINGLE-REACTION CASE (e.g. HNO4<->Nx,Hx)
! EQUAL TO MIN(RPRO,RLOSS)
! 1998 CHANGE:  MULTIPLIED BY FACTOR FOR EXCHANGE LIFETIME
! 2000 CHANGE:  IF BETA=0, DO ALSO FOR CASE WHERE IC2 NONZERO

        if(icx.le.0) then
!         do kk=1,c_kmax             ! kk vector loop
            ratex(kk) = cpro(kk,1,2)
            if(ratex(kk).gt.cpro(kk,2,1)) ratex(kk)=cpro(kk,2,1)
            if(cpro(kk,1,2).gt.0) then
              ratex(kk) = ratex(kk)*                                    &
     &         (cpro(kk,1,2)/(cpro(kk,1,2)+xc(kk,ic1)) )
                                      !if(cpro(kk,1,2).gt.0) then
            end if
!         end do                    ! kk vector loop
! EXCORR DEBUG WRITE
!           if(c_kkw.gt.0) write(c_out,621) ratex(c_kkw)
! 621         format(' EXCORR:  SINGLE SPECIES RATEX =', 1pe10.3)

                             !if(icx.le.0)
        end if

! IF IC2>0 AND GAS, TWO LINKED SPECIES.
! CALCULATE THE SIZE OF THE REDUNDENT EXCHANGE (RATEX):
!
!  (REDUNDENT EXCHANGE DERIVED FROM TWOSOLVE SOLUTION ABOVE.
!   REDUNDENT EX = CP(2->1) FROM SOLUTION WITH ZERO XR2 SOURCE (RP2=0)
!   PLUS CP(1->2) FROM MATRIX SOLUTION WITH ZERO INITIAL XR(1) (RP1=0).
!   FROM TWOSOLVE SOLUTION, ABOVE,
!       PARTIAL X2=XP2*(CP2*RP1)/(RL1*RL2 - CP1*CP2)
!       REDUNDANT 2->1EX = CP1'*XP2*CP2*RP1/denom.
!                        =CP1*CP2*RP1/denom.  SAME FOR 1->2EX.
!    )
!
! MODIFIED TO ALLOW AQUEOUS, SPECIAL EQUILIBRIUM SPECIES (2000)

        if(icx.gt.0) then

! ZERO AND SUM RPRO, RLOSS, XRP FOR TWO EXCHANGE SPECIES
          do  is=1,2
!           do kk=1,c_kmax         ! kk vector loop
              rloss(kk,is) = 0.
              rpro(kk,is)  = 0.
              xrp(kk,is)   = 0.
!             end do                ! kk vector loop
            ics = c_npequil(ic1)
            if( is.eq.2) ics = c_npequil(icx)
            do neq=1,(c_nequil(ics)+1)
              ic=ics
              if(neq.gt.1)ic=c_ncequil(ics,(neq-1))
!             do  kk=1,c_kmax        ! kk vector loop
                alpha(kk) = 1.
                if(neq.gt.1) alpha(kk)= c_h2oliq(kk)*avogadrl
                rloss(kk,is) = rloss(kk,is)+rrl(kk,ic)
                rpro(kk,is)  = rpro(kk,is) +rrp(kk,ic)
                xrp(kk,is)   = xrp(kk,is)  +xc(kk,ic)*alpha(kk)
                prior(kk) = prior(kk) +   c_xcin(kk,ic)*alpha(kk)
!             end do                ! kk vector loop
                             ! neq-1,(c_nequil(ics)+1)
            end do
                           ! is=1,2
          end do

! POSSIBLE ERROR, MUST SUBTRACT CPRO FROM RPRO - ELSE ITS INCLUDED!

! SOLUTION FOR RATEX.
!   (If denominator is zero, use single-species solution instead)

!         do kk=1,c_kmax        ! kk vector loop
            beta(kk) = (rloss(kk,1)+xrp(kk,1))*(rloss(kk,2)+xrp(kk,2))  &
     &                - cpro(kk,1,2)*cpro(kk,2,1)
            if(beta(kk).gt.0) then
              ratex(kk) = cpro(kk,1,2)*(cpro(kk,2,1)                    &
     &             *(rpro(kk,1)+rpro(kk,2) + prior(kk)               )  &
     &                 /beta(kk) )
! EXCORR DEBUG WRITE
!             if(c_kkw.gt.0) write(c_out,624) ratex(c_kkw)
! 624           format(' EXCORR:  TWO SPECIES FULL RATEX =', 1pe10.3)
! TEMPORARY EXCORR DEBUG WRITE - DETAILS
!             if(c_kkw.gt.0) write(c_out,625)
!    *          rloss(c_kkw,1), xrp(c_kkw,1), rloss(c_kkw,2)
!    *         , xrp(c_kkw,2), cpro(c_kkw,1,2), cpro(c_kkw,2,1)
! 625          format(
!    *           '  (EXCORR: rloss xrp1 rloss2 xrp2 cpro12 cpro21=)',
!    *               /, (8(1pe10.3)) )
!             if(c_kkw.gt.0) write(c_out,626)
!    *          rpro(c_kkw,1), rpro(c_kkw,2), prior(c_kkw), beta(c_kkw)
! 626           format('  (EXCORR: rpro1 rpro2 prior beta =)',
!    *        /, (8(1pe10.3)) )

            else
              ratex(kk) = cpro(kk,1,2)
              if(ratex(kk).gt.cpro(kk,2,1)) ratex(kk)=cpro(kk,2,1)
              if(cpro(kk,1,2).gt.0.) then
                ratex(kk) = ratex(kk)*                                  &
     &           (cpro(kk,1,2)/(cpro(kk,1,2)+xc(kk,ic1)) )
                                       !if(cpro(kk,1,2).gt.0.) then
              end if

! EXCORR DEBUG WRITE
!             if(c_kkw.gt.0) write(c_out,627) ratex(c_kkw)
! 627           format(' EXCORR:  TWO SPECIES SIMPLE RATEX =', 1pe10.3)

                             !  if(beta(kk).gt.0)
            end if
!         end do              ! kk vector loop

                     !if(icx.gt.0)
      end if

! PROTECT AGAINST RATEX>EXCHANGE, RPRO FOR TWO-REACTION CASE
!        do kk=1,c_kmax        ! kk vector loop
          if(ratex(kk).gt.cpro(kk,1,2)) ratex(kk)=cpro(kk,1,2)
          if(ratex(kk).gt.cpro(kk,2,1)) ratex(kk)=cpro(kk,2,1)
!        end do               ! kk vector loop

! UNDO LOOP FOR INDIVIDUAL REACTIONS;
! UNDO EXCHANGE PRODUCTION AND LOSS REACTIONS IN PROPORTION TO SIZES
! SO THAT TOTAL UNDO IN EACH DIRECTION EQUALS RATEX.

                         ! 120
        do  ii=1,5
                         ! 125
         do i=1,2
          if(i.eq.1) nr=c_exloss(ic1,nex,ii)
          if(i.eq.2) nr=c_expro(ic1,nex,ii)

! SET UNDO FOR INDIVIDUAL REACTION.
! NOTE DIVIDE-BY-ZERO DANGER.  RPRO, RLOSS SHOULD NEVER BE ZERO.
          if(nr.gt.0) then

            if(i.eq.1) then
!             do kk=1,c_kmax       ! kk vector loop
               undo(kk) = 0.
               if(cpro(kk,1,2).gt.0)                                    &
     &         undo(kk) = ratex(kk)*c_rr(kk,nr)/cpro(kk,1,2)
!             end do               ! kk vector loop
            else
!             do kk=1,c_kmax      ! kk vector loop
               undo(kk) = 0.
               if(cpro(kk,2,1).gt.0)                                    &
     &         undo(kk) = ratex(kk)*c_rr(kk,nr)/cpro(kk,2,1)
!             end do              ! kk vector loop
                           ! if(i.eq.1)
            end if

! UNDO LOSS FROM REACTANTS
!   2000 MODIFICATION:  UNDO FOR REAL REACTANTS, NOT GAS EQUIVALENTS
!    (npequil comment out)

           do  n=1,2
            ic = c_reactant(nr,n)
            if(ic.gt.0) then
!             ic=c_npequil(ic)
! 2005 CHANGE OPTION:  DON'T SKIP FOR MAIN SPECIES.
!   CAUSES ERROR IF MAIN SPECIES IS OFF CASCADE.
              if(ic.ne.ic1.and.ic.ne.icx) then
!             if(ic.ne.0 ) then
!
!               do kk=1,c_kmax     ! kk vector loop
                 rrl(kk,ic) = rrl(kk,ic) -undo(kk)
!               end do            ! kk vector loop

! EXCORR REGULAR DEBUG WRITE (REGULAR w/BRPRO)
!       if(c_kkw.gt.0) write(c_out, 513) c_tchem(ic),
!    *        rrl(c_kkw,ic), c_rr(c_kkw,nr), undo(c_kkw)
! 513     format('EXCORR IC RRL RR UNDO=  ',a8,2x,3(1pe10.3))

              end if
           end if
                       !do  n=1,2
           end do

!  UNDO PRODUCTION.
           if(c_nnpro(nr).gt.0) then
            do  n=1,c_nnpro(nr)
              ic = c_product(nr,n)
              if(ic.gt.0) then
!               ic=c_npequil(ic)
! 2005 CHANGE OPTION:  DON'T SKIP FOR MAIN SPECIES.
!   CAUSES ERROR IF MAIN SPECIES IS OFF CASCADE.
                if(ic.ne.ic1.and.ic.ne.icx) then
!               if(ic.ne.0                ) then
!
!                 do kk=1,c_kmax      ! kk vector loop
                   rrp(kk,ic) = rrp(kk,ic)  - c_stoich(nr,n)*undo(kk)
!                 end do             ! kk vector loop

! EXCORR REGULAR DEBUG WRITE (REGULAR w/BRPRO)
!       if(c_kkw.gt.0) write(c_out, 514) c_tchem(ic),
!    *        rrp(c_kkw,ic), c_rr(c_kkw,nr), undo(c_kkw)
! 514     format('EXCORR IC RRP RR UNDO=  ',a8,2x,3(1pe10.3))

                end if
              end if
                          !   do n=1,c_nnpro(nr)
            end do
                       !if(c_nnpro(nr).gt.0)
           end if

! UNDO ODD NITROGEN PRODUCTION AND ODD-H SENSITIVITY

!            do kk=1,c_kmax         ! kk vector loop
              senshx(kk,1) = 0.
              senshx(kk,2) = 0.
!            end do                ! kk vector loop

             do n=1,2
              ic = c_reactant(nr,n)
              if(ic.gt.0) then
                ic = c_npequil(ic)
                if(c_icat(ic).gt.0) then

!                 do kk=1,c_kmax     ! kk vector loop
                   senshx(kk,1) = senshx(kk,1)                          &
     &                               + senhcat(kk,c_icat(ic))
!                 end do            ! kk vector loop
                  if(c_icat(ic).ne.3) then
! kvec             do kk=1, kmax   ! kk vector loop
                    senshx(kk,2) = senshx(kk,2)                         &
     &                               + senhcat(kk, c_icat(ic))
! kvec             end do           ! kk vector loop
                  end if


                                !if(c_icat(ic).gt.0)
                end if
                             ! if(ic.gt.0)
              end if
  325        continue
                               !do n=1,2
             end do

             do n=1,2
!              do  kk=1,c_kmax          ! kk vector loop
                oddhdel(kk,n) = oddhdel(kk,n) - c_oddhx(nr,n)*undo(kk)  &
     &           *senshx(kk,n)
!              end do                  ! kk vector loop
                         !do n=1,2
             end do


             if(c_pronox(nr).gt.0) then
!              do  kk=1,c_kmax          ! kk vector loop
                sourcnx(kk) = sourcnx(kk)-c_pronox(nr)*undo(kk)
!              end do                  ! kk vector loop
                              ! if(c_pronox(nr).gt.0)
             end if
             if(c_pronox(nr).lt.0) then
!              do  kk=1,c_kmax          ! kk vector loop
                 sinknx(kk) =  sinknx(kk)-c_pronox(nr)*undo(kk)
!              end do                  ! kk vector loop
                              ! if(c_pronox(nr).lt.0)
             end if


! REGULAR DEBUG WRITE
!          if(c_kkw.gt.0) write(c_out,15592)  (c_treac(nrx,nr),nrx=1,5)
! 15592      format(/,'EXCORR:    ',a8,'+',a8,'=>',a8,'+',a8,'+',a8)
!          if(c_kkw.gt.0) write(c_out,15591) nr
!    *       , c_rr(c_kkw,nr),undo(c_kkw),
!    *     c_oddhx(nr,1), senshx(c_kkw,1),c_pronox(nr),
!    *      oddhsum(c_kkw,1),
!    *       oddhdel(c_kkw,1), sourcnx(c_kkw), sinknx(c_kkw)
!    *       ,rrp(c_kkw,9),rrl(c_kkw,9)
! 15591      format('EXCORR:  NR   RR  UNDO ',i5,2(e10.3),/,
!    *     '  ODDHXFAC SENSHX PRONOX   ODDHSUM  ODDHDEL SOURCNX SINKNX',
!    *     ' RP9 RL9',/,2f5.2,(8(e10.3)))



                    !if(nr.gt.0)
          end if
                          !do i=1,2         125
         end do
                        !do  ii=1,5        120
        end do
! END UNDO LOOP FOR INDIVIDUAL REACTIONS


                !do nex=1,20  MAIN LOOP 1000
      end do
! END MAIN LOOP  FOR  MULTIPLE EXCHANGED SPECIES

! END EXCORR
 2000   return
      END
! --------------------------------
!
!

      subroutine noxsolve(ic1,ic2,ic3)
!                         O3  NO2  NO

! Special solution for concentrations of O3, NO2 and NO.
!
! This uses reaction rates, sums of RLOSS, gas-aqueous sums
!   and cross-production (CPRO)  from CHEMSOLVE.
!
! FUTURE OPTION:  Flag to keep NOx at pre-set value,
!                  while adjusting NO and NO2
!                 (fails so far.  Set SOURCNX = SINKNX?)
!
! NOTE:  THIS SUBROUTINE MAY NEED TO USE R12: OH+NO2->HNO3 SPECIAL.
!
!
! Inputs:    Species numbers (ic) for O3, NO2, NO.
!            Also uses:
!            Species sums for production, loss and cross-production
!            (xrpm, rlm, rpm, cpm) from MULTISOLVE part of CHEMSOLVE.
!            NOx sums (sourcnx, sinknx) from full program.
!
! Outputs:  xrrm:  concentrations for O3, NO, NO2.
!
!           (used in MULTISOLVE part of CHEMSOLVE
!             to create updated species solution array
!             with gas/aqueous partitioning)
!
! Called by:    chemsolve (as alternative species solution)
!
! Calls to:  None.
!
! ---------------------------------------------
! History:
!  12/06 Written by Sandy Sillman from boxchemv7.f
!
! -------------------------------------------------------------------
!
!
! ---------------------------------------------
      implicit none

! LOCAL VARIABLES

! xnox     NOx concentration (NO+NO2) molec/cm3
! xox      Ox concentration  (O3+NO2) molec/cm3

                                        ! NOx, molec/cm3
      double precision xnox(c_kvec)
                                        !  Ox, molec/cm3
      double precision xox(c_kvec)

                                  ! Prior Ox for write
      double precision oxox
                                  ! Ox source for write
      double precision sourcox
                                  ! Ox sink  for write
      double precision sinkox

                                  ! Quadratic parameter for write
       double precision xk2
                                  ! Quadratic parameter for write
       double precision xk2n
                                  ! Quadratic parameter for write
       double precision xrln
                                  ! Quadratic parameter for write
       double precision xjn
                                  ! Quadratic parameter for write
       double precision xjnx
                                  ! Quadratic parameter for write
       double precision xrpn
                                  ! Sum pans for write
       double precision pansum
                                  ! Sum hno2 hno4 for write
       double precision hnosum


! ---------------------------------------------
      kk=1


! FIRST:  SOLVE FOR NOX.  USE ODDNSUM = CHEM PRODUCTION OF NOX
!  (excluding NO-NO2 conversions and NOx sinks).
! SOURCNX = NOX SOURCE WITH PRIOR.
! SINKNX = NOX SINKS, IGNORING NO-NO2 BACK-FORTH. (ALSO W/PRIOR)
! XNOXN = SOURCE/(SINK/XNOX)

!     do 16013 kk=1,c_kmax
        sourcnx(kk) = sourcnx(kk) +   c_xcin(kk,ic2)+  c_xcin(kk,ic3)
        sinknx(kk) =   xrm(kk,2) +  xrm(kk,3) - sinknx(kk)

        xnox(kk) = ( xrm(kk,  2)+ xrm(kk,  3))*sourcnx(kk)/sinknx(kk)

! OPTION:  INSERT THIS LINE FOR PRESET NOx CONCENTRATION
!       xnox(kk) =   c_xcin(kk,ic2)+  c_xcin(kk,ic3)

16013 continue

! NOXSOLVE DEBUG WRITE
       if(c_kkw.gt.0) write (c_out, 1851)                               &
     &      c_xcin(c_kkw,ic1),   c_xcin(c_kkw,ic2),   c_xcin(c_kkw,ic3),&
     &    xrm(c_kkw,1),  xrm(c_kkw, 2), xrm(c_kkw,3),                   &
     &    xnox(c_kkw), sourcnx(c_kkw), sinknx(c_kkw)
 1851  format(/,' NOXSOLVE DEBUG: ',/,                                  &
     &       ' INITIAL XXO: O3, NO2,NO  = ',3(1pe10.3),/,               &
     &       ' PRIOR XRM:   O3, NO2,NO  = ',3(1pe10.3),/,               &
     &       ' XNOX (=) SOURCNX (/) SINKNX  = ',3(1pe10.3)    )

! **** CHECK XRP AND XXO IN RPRO, RLOSS!!


! SENHCAT FOR NOX.  (PRIOR, dHx/dNOx dNOx/dOH product added to SENH.
!                    REPLACED, just include dNOx/dOH in HxDELTA sum.)
! THIS IS FROM THE NOX EQUATION:  NOXPRO=a+bOH
! dlnNOx/dlnOH = -[(OH+NO2) + sencatHO2*otherNOx losses]/ total loss;
!                                        total loss includes XRP(NOx).
!
! OPTIONS: USE REACTION R12 (OH+NO2->HNO3 EXPLICITLY.

!      do 16016 kk=1,c_kmax

! OPTION WITH R-12
!       senhcat(kk,12) = 0.- (  c_rr(kk,12)
!    *  + senhcat(kk,10)
!    *       *(sinknx(kk)-c_rr(kk,12)- xrm(kk,  2)- xrm(kk,  3))
!    *                  )/sinknx(kk)
! OPTION WITHOUT EXPLICIT R-12
        senhcat(kk,12) = 0.- (                                          &
     &  + senhcat(kk,10)*(sinknx(kk)        - xrm(kk,  2)- xrm(kk,  3)) &
     &                  )/sinknx(kk)
! END OPTION

        senhcat(kk,13) = senhcat(kk,12)
16016  continue

! STEADY-STATE.  THERE IS NO STEADY-STATE OPTION FOR NOX, ->INFINITE.
! BUT ISTS(NOX) CAN BE USED TO SET NOX EQUAL TO CONSTANT VALUE.
!  (FAILS 1999 - MUST USE HARD-WIRE OPTION, ABOVE.)
      if(c_lsts(ic3)) then
!       do 16023 kk=1,c_kmax
         xnox(kk) =  xrm(kk,  2)+ xrm(kk,  3)
         senhcat(kk,12) = 0.
         senhcat(kk,13) = 0.
16023   continue
      end if

! ODD OXYGEN (XOX):  SOLVE USING BACK-EULER: OX = RP/(RL/XRP).
! RP AND RL FOR ODD OXYGEN EQUAL THE SUM OF RP FOR O3 AND NO2
! WITH CROSS-CONVERSIONS (O3->NO2 AND NO2->O3) REMOVED.
! IN CHEMSOLVE(O3,NO2,NO), CROSS-PRODUCTION IS ADDED TO CPRO, NOT RPRO,
!  BUT IT IS ALSO INCLUDED IN RLOSS.  SO RLOSS IS CORRECTED.

! PRELIMINARY:  ADD NO-to-NO2 conversions to RPM(NO2)
!  These are equal to CPM(NO->NO2) minus CPM(O3->NO2)
!  They count as Ox production
!  They also count in the solution for NO,
!      which separates out O3+NO<->NO2 only.
!
! CHANGE:  WITH RPM INCLUDING CPM:
! PRELIMINARY:  REMOVE O3+NO<=>NO2 from RPM.
!     (Removal is CPM(1->2) and (2->1).  NOT (3->1).
!       In original version, 3->1 is zero.  Why?? - error)
!   RPM includes all CPM. Other NO-to-NO2 count for Ox and NO solutions.

!     do kk=1,c_kmax         ! kk vector loop
! ORIGINAL
!       rpm(kk,2) = rpm(kk,2) + cpm(kk,3,2) - cpm(kk,1,2)

! OPTION
        rpm(kk,2) = rpm(kk,2) - cpm(kk,1,2)
        rpm(kk,1) = rpm(kk,1) - cpm(kk,2,1)
        rpm(kk,3) = rpm(kk,3) - cpm(kk,2,1)
!
! TEMPORARY BUG FIX:  O3+NO->NO2 COUNTED DOUBLE IN ORIGINAL ALGORITHM
!   CORRECT HERE.  NOXBUG - delete when CPM is correct
!       rpm(kk,2) = rpm(kk,2) - cpm(kk,1,2)

!     end do                ! kk vector loop

!   NOXSOLVE DEBUG WRITE
      if(c_kkw.gt.0) write(c_out,1854)                                  &
     &     rpm(c_kkw,1), rpm(c_kkw,2), rpm(c_kkw,3),                    &
     &     rlm(c_kkw,1), rlm(c_kkw,2), rlm(c_kkw,3),                    &
     &     cpm(c_kkw,1,2), cpm(c_kkw,2,1),                              &
     &     cpm(c_kkw,3,2), cpm(c_kkw,2,3),                              &
     &     cpm(c_kkw,1,3), cpm(c_kkw,3,1)
 1854  format(/,' NOXSOLVE DEBUG:  (NO->NO2 added to rpNO2) ',/,        &
     &    ' RPM   O3, NO2, NO =  ', 3(1pe10.3), /,                      &
     &    ' RLM   O3, NO2, NO =  ', 3(1pe10.3), /,                      &
     &    'CPM O3->NO2, NO2->O3 = ',2(1pe10.3)   , /,                   &
     &    'CPM NO->NO2, NO2->NO = ',2(1pe10.3)   , /,                   &
     &    'CPM O3->NO , NO ->O3 = ',2(1pe10.3)   )

!     do kk=1,c_kmax         ! kk vector loop
        xox(kk) = ( xrm(kk,  1)+ xrm(kk,  2)) *                         &
     &                       ( rpm(kk,  1)+ rpm(kk,  2))                &
     &   /(  rlm(kk,  1)+  rlm(kk,  2)- cpm(kk,1,2)- cpm(kk,2,1) )

! OPTION:  INSERT THIS LINE FOR PRESET Ox CONCENTRATION
!  NOTE - ALSO CHANGE 'PRESET' OPTION IN presolve
!       xox(kk) =   c_xcin(kk,ic1)+  c_xcin(kk,ic1)

!     end do                ! kk vector loop

! NOXSOLVE DEBUG WRITE
      if(c_kkw.gt.0) write(c_out,1855) xox(c_kkw)
 1855  format(' NOXSOLVE XOX (= xrp*rpm/(rlm-cpm)) = ', 1pe10.3)

! --------------------------------------
! NO:  SOLVE BACKWARD EULER EQUATION FOR NO AS FUNCTION OF OX, NOx.
!
! THE EQUATION:  RP" + r1*NO2 = RL" + r2*NO*O3  BECOMES
!  RP" + r1*(NOx-NO) = RL"*NO + r2*NO*(Ox-NOx+NO).
!  WHERE RP", RL" = production, loss of NO (including NO->NO2)
!      but without R1:  NO2->NO+O3 and R2: NO+O3->NO2.
!
!  THIS PROVIDES A QUADRATIC FOR NO, SINCE Ox, NOx VARY SLOWLY.

!  SUBSTITUTE CPRO(O3->NO2) = r1*NO2prior;
!             CPRO(NO2->O3)=r2*O3p*NOp, w/ aq sums.
!
!  -> RP" + CP21(NOx-NO)/NO2p = RL"*NO + CP12*[(Ox-NOx+NO)/O3p]*[NO/NOp]
!
!  -> RP" + CP21(NOx/NO2p) = NO* [RL" + CP21/NO2p + CP12*(Ox-NOx)/(O3p*N
!                          +NO^2 *[CP12/(O3p*NOp)]
!
!  JANUARY 2005: SOLVE THIS QUADRATIC WITH THE FOLLOWING SUBSTITUTIONS:
!
!   RP" = rpm3  = p(NO), excluding NO2+hv.  (NO2+hv goes to cpro, not rp
!   RL" = (rlm3 - cpm(1,2).  rlm3 includes all losses of NO.
!          subtract cpm12 (not cpm32) because cpm12 is O3+NO->NO2 exactl
!                   (cpm32 includes NO+HO2=>NO2)
!  CP21, CP12 = cpm(1,2), cpm(2,1)
!
!   NOTE:  DIVIDES ADD COMPUTER TIME BUT PREVENT OVERFLOWS
! --------------------------------------

!     do 16036 kk=1,c_kmax
       alpha(kk) =  cpm(kk,1,2)/( xrm(kk,3)* xrm(kk,1))
       gamma(kk) =    rpm(kk,3)                                         &
     &           + ( cpm(kk,2,1)/ xrm(kk,2)) * xnox(kk)
       beta(kk) = (  rlm(kk,3) -  cpm(kk,1,2))/ xrm(kk,3)               &
     &          +  cpm(kk,2,1)/ xrm(kk,2)                               &
     &      + ( cpm(kk,1,2)/( xrm(kk,1)* xrm(kk,3)))                    &
     &           * (xox(kk)-xnox(kk))

        xrrm(kk, 3) = 0.5* (                                            &
     &           sqrt(beta(kk )**2 + 4.*alpha(kk )*gamma(kk ) )         &
     &           - beta(kk )                                            &
     &                    )/alpha(kk )

        xrrm(kk, 2) = xnox(kk) - xrrm(kk, 3)
        xrrm(kk, 1) = xox(kk) - xrrm(kk, 2)

! ATTEMPTED NOXBUG FIX: IF O3<0.
!  ASSUME THAT O3+NO2->NO3 IS CAUSE,  it represents 2*Ox loss, 1*NOx los
!  USE BACK-EULER TO SET O3
!  FUTURE - ADD BETTER CRITERIA, TAKE WHICHEVER-IS-LOWER ESTIMATE?

        if(xrrm(kk,1).lt.0.001*xrm(kk,1)) then
          xrrm(kk,1) = xrm(kk,1)                                        &
     &           *( rpm(kk,1)/rlm(kk,1))
        end if


16036 continue

! NOXSOLVE DEBUG WRITE
       if(c_kkw.gt.0) write (c_out,1858)                                &
     &      alpha(c_kkw), beta(c_kkw), gamma(c_kkw)
 1858  format(' NOXSOLVE DEBUG: ',/,                                    &
     &  '     ALPHA = (cp:O3->NO2)/(O3*NO) =    ',1pe10.3,/,            &
     &  '     BETA  =                           ',1pe10.3,/,            &
     &  '     GAMMA = rpNO+(cpNO2->O3)*NOx/NO2 =', 1pe10.3  )

! NOXTEST:  IF KMAX=1 ONLY; SAVE TEST RATIO FOR NO2 vs PRIOR NO2
        c_notest = abs(1.-xrrm( 1, 2)/ xrm( 1,  2))

!  WRITE OPTION - WRITE SUMMARY FOR NOX-OX HERE
!   (STANDARD OUTPUT)

      if(c_kkw.gt.0) then

       write(c_out,1901)  ic1,ic2,ic3
 1901 format(//, '   NOXSOLVE IC=',3i3)
      write(c_out,1902)
 1902 format('NOX ANALYSIS:',/,'   O3        NO2       NO     ',        &
     & '   NO3       HNO3      PANs      HONO-HNO4  '        )

      pansum = 0.
      hnosum = 0.
      do 1910 ic=1,c_nchem2
       if(c_icat(ic).eq.5) pansum=pansum+xc(c_kkw,ic)
       if(c_icat(ic).eq.6) hnosum = hnosum+xc(c_kkw,ic)
 1910 continue

      write(c_out,1911) xrrm(c_kkw,1),xrrm(c_kkw,2),xrrm(c_kkw,3),      &
     & xc(c_kkw,c_nno3     ),xc(c_kkw,c_nhno3    ),pansum,hnosum
 1911 format(8(1pe10.3))

      write(c_out,1904)
 1904 format(/,'PRIOR O3     NO2        NO')
      write(c_out,1911)  xrm(c_kkw,1), xrm(c_kkw,2), xrm(c_kkw,3)

      write(c_out,1905)
 1905 format(/,'RPRO  O3     NO2        NO')
      write(c_out,1911)  rpm(c_kkw,1), rpm(c_kkw,2), rpm(c_kkw,3)

      write(c_out,1906)
 1906 format(/,'RLOSS (including NO+O3<->NO2)')
      write(c_out,1911)   rlm(c_kkw,1),  rlm(c_kkw,2),  rlm(c_kkw,3)

      write(c_out,1907)  cpm(c_kkw,2,1), cpm(c_kkw,1,2),                &
     &      sourcnx(c_kkw),sinknx(c_kkw)
 1907 format(/,'CPRO:  NO2+hv ->',(1pe10.3),/,                          &
     &         '       NO+O3  ->',(1pe10.3),/,                          &
     &         'NOXPRO        = ',(1pe10.3),/,                          &
     &         'NOXLOSS       = ',(1pe10.3))

      write(c_out,1908)
 1908 format(/,'ANALYSIS:',/,                                           &
     & '   XNOX  =  SOURCNX / (SINKNX / XNOXP----------)')
      write(c_out,1911) xnox(c_kkw),sourcnx(c_kkw),sinknx(c_kkw),       &
     &     xrm(c_kkw,ic2),  xrm(c_kkw,ic3)

        oxox   =  xrm(c_kkw,ic1)+ xrm(c_kkw,ic2)
        sourcox =   rpm(c_kkw,  1)+ rpm(c_kkw,  2)
        sinkox =    rlm(c_kkw,  1)+  rlm(c_kkw,  2)                     &
     &              - cpm(c_kkw,  2,1)- cpm(c_kkw,  1,2)
      write(c_out,1909)
 1909 format(/,'   XOX   =   OXPRO / (OXLOSS / OXP)')
      write(c_out,1911) xox(c_kkw),sourcox, sinkox,oxox


! QUADRATIC ANALYSIS:  xk2 + (xk2n+xrln) = xjnx + xrpn
!                     (~NO**2)  (~NO)        (~1)
!                   alpha*NO**2 + beta*NO = gamma  with new NO.

      if(xrrm(c_kkw,3).eq.0) xrrm(c_kkw,3)=1.
      xk2 = (xrrm(c_kkw,3)**2) * alpha(c_kkw)
      xk2n = xrrm(c_kkw,3)                                              &
     &   *( cpm(c_kkw,1,2)/( xrm(c_kkw,1)* xrm(c_kkw,3)))               &
     &                          * (xox(c_kkw)-xnox(c_kkw))
      xrln = xrrm(c_kkw,3)                                              &
     &          * (  rlm(c_kkw,3) -  cpm(c_kkw,1,2))/ xrm(c_kkw,3)
      xjn = xrrm(c_kkw,3)   *   cpm(c_kkw,2,1)/ xrm(c_kkw,2)
      xjnx =       ( cpm(c_kkw,2,1)/ xrm(c_kkw,2)) * xnox(c_kkw)
!     xrpn =  rpm(c_kkw,3)+ rpm(c_kkw,2)
      xrpn =  rpm(c_kkw,3)

      write(c_out,1912)
 1912 format(/, 'NO ANALYSIS:  QUADRATIC EQUATION w/ k: NO+O3<->NO2',/, &
     & ' alpha*NO**2 +  beta........beta.....beta*NO  =  gamma...gamma' &
     &,/,                                                               &
     & ' k2*NO**2  k2*NO*(Ox-NOx) otherL*NO    j1*NO   j1*NOx   rpNO')
      write(c_out,1911) xk2, xk2n, xrln, xjn,xjnx,xrpn
      write(c_out,1913)
 1913 format(/,' alpha       beta     gamma                  ')
      write(c_out,1911) alpha(c_kkw), beta(c_kkw), gamma(c_kkw)


      end if

! ZERO PROTECT: THIS ALGORITHM SHOULD NEVER GENERATE NEGATIVE
! UNLESS THERE IS A MATH ERROR OR TINY NUMERICAL NEGATIVE.
!        do 16043 kk=1,c_kmax
          if(xrrm(kk,1).le.0) then
           xrrm(kk,1)=0.001
          end if
16043    continue
!        do 16046 kk=1,c_kmax
          if(xrrm(kk,2).le.0) then
           xrrm(kk,2)=0.001
          end if
16046    continue
!        do 16049 kk=1,c_kmax
          if(xrrm(kk,3).le.0) then
           xrrm(kk,3)=0.001
          end if
16049    continue

! NOTE:  SAVE PRIOR AS XNO, XNO2, XO3?

! DIFFICULT CONVERGENCE AID:
! AVERAGE O3, NO2, NO WITH PRIOR TIME STEP HERE IF DESIRED.
!  - note 2009 ALTERNATIVE below.

       if(c_iter.gt.5) then
!      if(c_iter.eq.-1) then
!        do 16053 kk=1,c_kmax
          xrrm(kk ,3) = 0.5*( xrm(kk,3 )+xrrm(kk,3) )
          xrrm(kk ,1) = 0.5*( xrm(kk,1 ) +xrrm(kk,1) )
          xrrm(kk ,2) = 0.5*( xrm(kk,2 )+xrrm(kk,2) )
16053    continue
        end if

! 2009 NOX CONVERGENCE OPTION/ALTERNATIVE:  SETGEOM
!  adjust based on history of NOx.  (or Ox).
!
!  Note, alt:  geom adjust xnox, xox above? No.
!        cannot do separate geom. avg for NOx; O3-NO-NO2 must be all tog

!      if(c_iter.ge.4) then
       if(c_iter.eq.-1) then
         call setgeom(ic2)
                           !if(c_iter.ge.4) then
       end if
!      do kk=1, c_kmax          ! kk vector loop
          xrrm(kk ,3) =(xrrm(kk ,3)  **geomavg(kk,ic2) )                &
     &                * (xrm(kk ,3)    **(1.-geomavg(kk,ic2)) )
          xrrm(kk ,1) =(xrrm(kk ,1)  **geomavg(kk,ic2) )                &
     &                * (xrm(kk ,1)    **(1.-geomavg(kk,ic2)) )
          xrrm(kk ,2) =(xrrm(kk ,2)  **geomavg(kk,ic2) )                &
     &                * (xrm(kk ,2)    **(1.-geomavg(kk,ic2)) )
                                                          ! NOx
         history(kk,ic2,c_iter) = xrrm(kk,2)+xrrm(kk,3)
!      end do                  ! kk vector loop

       if(c_kkw.gt.0) write(c_out,*) 'NOx geomavg =',                   &
     &      geomavg(c_kkw,ic2)



! END NOXSOLVE
 2000 return
      END
! ---------------------------------------------
!

      subroutine ohsolve(ic1,ic2,ic3)
!                       (OH, HO2, H2O2)
!
! Radical balance solution for odd-hydrogen radicals:
!   OH and HO2, also with adjustment for H2O2 and CO3 (aq)
!
! This uses the algorithm from Sillman, 1991 (J. Geophys. Res.)
!
! Critical parameters are:
!   oddhsum:  prior sum of radical net production-loss
!   oddhdel:  prior sum weighted by d(lnHx)/d(lnOH)
!             = sensitivity of radical sum to OH.
!
! These form a linear sum (A+B*OH) for net radical production
!   which is used to solve for OH
!
! (Note:  change in Hx concentration is also added to oddhsum
!   for a non-steady-state solution).
!
! Solution is also adjusted by geometric mean with prior iteration
!   with geometric mean parameter set by iteration history (setgeom)
!
! The following solutions are generated:
!
!   OH is solved from the radical balance equation.
!
!   HO2 is solved from OH/HO2 in the production/loss equation for OH.
!
!   Both are partitioned between gas and aqueous species.
!
!   CO3 (aq) is adjusted based on the radical balance.
!
!   H2O2 is solved here by a normal call to CHEMSOLVE
!     (needed only to insure H2O2 is solved in the proper order)
!
! 2005 CHANGE:  USE RRP, RRL, where RP, RL IS SET TO ZERO.
!
! Inputs:    Species numbers (ic) for OH, HO2, H2O2
!            Also uses:
!             oddhsum, oddhdel, oddhsrc, oddhloh, oddhlho2
!            (oddhsump, oddhfacp calculated during prior iteration -not
!
! Outputs:  xc:    concentrations for OH and HO2
!
!
! Called by:    quadchem
!
! Calls to:     chemsolve (to solve H2O2)
!               setgeom
!
! ---------------------------------------------
! History:
!  12/06 Written by Sandy Sillman from boxchemv7.f
!
! -------------------------------------------------------------------
!
! ---------------------------------------------------
!
      implicit none

!
! LOCAL VARIABLES:
!
! LOCAL VARIABLES USED IN SOLUTION

! foh(kk)           OH/HO2 ratio (declared in 'chemlocal.EXT')
! foh1(kk)          OH/HO2 ratio from prior iteration
! foh1a(kk)         Production of HO2 from OH->HO2 conv, molec/cm3
! foh1b(kk)         Production of HO2 from other sources, molec/cm3
!
! ncsol(kk)              Species list passed to solver subroutine
!
! oddhfac(kk)       Calculated factor for updating OH:
!                        (OH = OHp*oddhfac)
!
                                       ! OH/HO2 from prior iteration
      double precision foh1(c_kvec)
                                       ! Prod HO2 from OH, mol/cm3
      double precision foh1a(c_kvec)
                                       ! Prod HO2 from other, mol/cm3
      double precision foh1b(c_kvec)
                                        ! Factor for updating OH
      double precision oddhfac(c_kvec)

                                         ! Factor for updating OH - w/RO
      double precision oddhfac1(c_kvec)
                                         ! Factor for updating OH - w/o
      double precision oddhfac2(c_kvec)
                                         ! Weighing Factor for oddhfac 1
      double precision oddhro2f(c_kvec)

! moved to chemlocal.EXT
!     double precision oddhfacp(c_kvec) ! Factor for OH from prior itera
!     double precision oddhsump(c_kvec) ! Net pro/loss of OH from prior
!
                                  ! Species list passed to chemsolve
      integer ncsol(c_cdim)
                                  ! Function to return chem index ic
      integer namechem

! LOCAL VARIABLES USED  FOR WRITTEN OUTPUT ONLY
                                  ! Sum for written output
      double precision pansum
                                  ! Sum for written output
      double precision hnosum
                                  ! Sum for written output
      double precision xrooh
                                  ! Sum for written output
      double precision xhno4
                                  ! Sum for written output
      double precision xhno3
                                  ! Sum for written output
      double precision xco3
!
!
! ---------------------------------------------------
             kk=1


! PRELIMINARY OPTION:  SOLVE H2O2 BY A NORMAL CALL TO CHEMSOLVE.
!  NOTE:  H2O2 HAS A SPECIAL TREATMENT WITHIN CHEMSOLVE
!  THIS INSURES THAT NET PRODUCTION OF H2O2 IS NO GREATER THAN HX SOURCE

      ncsol(1) = ic3
      do ic=2,nsdim
        ncsol(ic) = 0
      end do
      call chemsolve(ncsol)
!
! PRELIMINARY:  CALCULATE REMAINING ODD-H REACTION RATES AND HX SUMS.
! INVOKE CHEMSOLVE FOR (OH,-3,HO2) AND (OH,-1,HO2).
! THE RESULTING XRP, RPRO, RLOSS ARE USED BELOW.

! (NOTE SWITCHED ORDER FOR MAY 1995.  CALC RATES, RP, RL BEFORE RLOSS.)


! 2005:  PRELIMINARY CALL TO CHEMSOLV REPLACED - ADD IN HERE
!  Add for do ic=1,3,2  => oh, ho2
!  Generate rrp, rrl (include products)
!  Generate rpro, rloss, xrp
!  Zero rrp, rrl.

! -----------
! PRELIMINARY CALCULATION: REMAINING REACTIONS AND XR, RP, RL SUM
! -----------
!  SUM INTO RLOSS, RPRO, XRP (w/ ST ST ADJUSTMENT)
!  AND ZERO RP, RL
!  ADOPTED FROM CHEMSOLVE

       do is=1, 3, 2
         ics = ic1
         if(is.eq.3) ics = ic2

! REACTIONS
         if(c_nnrchem(ics).gt.0) then
           do i=1,c_nnrchem(ics)
             nr =  c_nrchem(ics,i)
             call brpro(nr)
                        !do i=1,c_nnrchem(ics)
           end do
                      !if(c_nnrchem(ics).gt.0)
         end if

         if(c_nnrchp(ics).gt.0) then
           do     i=1,c_nnrchp(ics)
             nr = c_nrchmp(ics,i)
             call brpro(nr)
           end do
         end if


! ZERO RUNNING SUMS
!           do  kk=1,c_kmax           ! kk vector loop
             rpro(kk,is) =  0.
             rloss(kk,is) = 0.
             xrp(kk,is) = 0.
!           end do                   ! kk vector loop

! ESTABLISH RPRO, RLOSS AND XRP FOR THE 'BASE' SPECIES
!        do kk=1,c_kmax      ! kk vector loop
          rpro(kk,is) = rpro(kk,is)+  rrp(kk, ics) +   c_xcin(kk,ics)
          rloss(kk,is) =rloss(kk,is)+  rrl(kk, ics)
          xrp(kk,is) =  xrp(kk,is) +  xc(kk,ics)
!        end do               ! kk vector loop

! ADD ALL AQUEOUS-EQUILIBRIUM SPECIES INTO SUMMED RPRO, RLOSS AND XRP.
! CONVERTING AQUEOUS INTO GAS UNITS (AVOGADRL)
         if(c_nequil(ics).gt.0)       then

           do  neq=1,c_nequil(ics)
             ic = c_ncequil(ics,neq)
!            do kk=1,c_kmax    ! kk vector loop
               xrp(kk,is) =   xrp(kk,is)                                &
     &                       + xc(kk,ic)*c_h2oliq(kk)*avogadrl
               rpro(kk,is) = rpro(kk,is) + rrp(kk,ic)
               rloss(kk,is) = rloss(kk,is)+rrl(kk,ic)
!            end do           ! kk vector loop
                         ! do neq=1,c_nequil(ics)
           end do
         end if

! NONSTEADY STATE ADJ:  IF NONSTEADY STATE OR ZERO RLOSS, ADD XRP to RPR

!        do kk=1,c_kmax      ! kk vector loop
          if(.not.c_lsts(ics).or.rloss(kk,is).eq.0)                     &
     &          rloss(kk,is) = rloss(kk,is) + xrp(kk,is)
          if(rloss(kk,is).le.0.) rloss(kk,is) = 1.0e-08
!        end do                       ! kk vector loop

! RECORD RP, RL AND ZERO RRP, RRL
!  NOTE:  RRP, RRL represent running sum through cascade.
!         RP, RL represent final sum through cascade.
!  SUBSEQUENT OH CALCULATION uses final sum (RP, RL), not RRP, RRL.

         do  neq=1,(c_nequil(ics)+1)
           ic=ics
           if(neq.gt.1) ic=c_ncequil(ics,(neq-1))
           c_rp(kk, ic) = rrp(kk,ic)
           c_rl(kk,ic) = rrl(kk,ic)
           rrp(kk,ic) = 0.
           rrl(kk,ic) = 0.
                            !do  neq=1,(c_nequil(ics)+1)
         end do

                    !do is=1, 3, 2
       end do

! 2009 CORRECTION?
! RECORD RP, RL AND ZERO RRP, RRL for H2O2?
! GOT HERE.
!
! c_rp(h2o2) should have been set in call to chemsolve, and should be
!  consistent. It seems bad. Or is it the very low NO?
!  NO+HO2 8e-12  6e4 7e2  (->4e2) 1.8e3  -> 6e-1
! HO2+HO2 2e-12 7e2 7e2 1.8e3  -> 2e-3  correct in REACTION RATE
!
!  but alpha, beta very different!  unit change?
! round 2 rl -ho2 is much much lower, rp H2O2 unchanged.
!
! Q:
!  Is there a unit change, or a problem with rrp, rrl?
!  Try senhcat=1, does this help?
! Try oddhfac1, 2 and use rlHO2/*+rpH2O2 to scale
!
! -----------
! END LOOP - PRELIMINARY CALCULATION OF RP, RL
! -----------

! ------------
!  PRELIMINARY:  ADD PRIOR OH, HO2, RO2 INTO ODDHSUM, ODDHDEL
! ------------
! FIRST:   ADD PRIOR OH, HO2, RO2 INTO ODDHSUM, ODDHDEL
!   (XR DOES NOT INCLUDE AQ SUM.  JUST RPRO, XRP, ETC.)
!  CHANGE 1195:  DO NOT INCLUDE PRIOR SUM IF STEADY STATE
!
!  CHANGE 1195:  PRIOR ODDHDEL.  If RP, RL is small, then there
!    PRIOR ODDH shows little sensitivity to OH.
!  This was solved by changing PRIOR ODDHDEL here and SENCAT below.
!  JULY 1996:  PRIOR ODDHDEL = XR or (RP+RL), whichever is smaller.
!  JULY 1996:  INCLUDE AQUEOUS IN PRIOR ODDHSUM AND ODDHDEL.

!  (NOTE:  COPY THIS SECTION TO 'PRIOR' IN OHWRITE.)

! 2005 CHANGE:  This is now done AFTER OH, HO2 reactions processed into
!  NOTE:  This uses FINAL RP, RL rather than running sum RRP, RRL
!         since RRP, RRL have been set to zero.
!
! 2009 CHANGE: Do not count lumped species accumulators in PRIOR Hx sum.

      do ic=1,c_nchem2

        if((c_icat(ic).eq.3.or.c_icat(ic).eq.9.or.c_icat(ic).eq.10      &
     &             .or.c_icat(ic).eq.8 ).and.                           &
     &          .not.c_lsts(ic).and. .not.c_llump(ic))  then


         if(ic.eq.c_npequil(ic)) then
! kvec     do       kk=1,c_kmax       ! kk vector sum
            oddhsum(kk,1) = oddhsum(kk,1)                               &
     &                   +   c_xcin(kk,ic) - xc(kk,ic)


            alpha(kk)=0.
! kvec     end do                      ! kk vector sum
! kvec     do       kk=1,c_kmax       ! kk vector sum
            if(c_rl(kk,ic)+xc(kk,ic).gt.0) then
             alpha(kk) =  (c_rp(kk,ic)+c_rl(kk,ic))*xc(kk,ic)           &
     &           /(c_rp(kk,ic)+c_rl(kk,ic)+xc(kk,ic))

!   TEMPORARY 2005 BUG CHANGE!!!! 2005 -
!     SHOULDN'T oddhdel include PRIOR MINUS ANY SENSITIVITY????
!            alpha(kk) =  (xc(kk,ic)          )*xc(kk,ic)
!    *           /(c_rp(kk,ic)+c_rl(kk,ic)+xc(kk,ic))

             oddhdel(kk,1) = oddhdel(kk,1)                              &
     &             - senhcat(kk,c_icat(ic)) * alpha(kk)
! TEMPORARY DEBUG WRITE
!            if(c_kkw.gt.0) write(c_out, 11019)
!    *        c_tchem(ic),c_icat(ic), xc(c_kkw,ic)
!    *       ,   c_xcin(c_kkw,ic), alpha(c_kkw)
!    *       , senhcat(c_kkw,c_icat(ic)), oddhsum(c_kkw,1),
!    &          oddhdel(c_kkw,1)
!    &         ,oddhsum(c_kkw,2), oddhdel(c_kkw,2)
! 11019        format('OHSOLVE: CHEM ICAT  XR XXO DelFAC SENHCAT',
!    *                           /,a8,i4,4(1Pe10.3),/,
!    *        ' ODDHSUM1 ODDHDEL1, ODDHSUM2, ODDHDEL2=',7(1Pe10.3))


            end if
! kvec     end do                      ! kk vector sum
                                 ! if(ic.eq.c_npequil(ic)) then
         else

!

           if(c_h2oliq(kk).gt.0) then
! kvec       do kk=1,c_kmax           ! kk vector sum
               oddhsum(kk,1) = oddhsum(kk,1)                            &
     &       + (  c_xcin(kk,ic) - xc(kk,ic)) *c_h2oliq(kk)*avogadrl
               alpha(kk)=0.
! kvec       end do                      ! kk vector sum
! kvec       do kk=1,c_kmax           ! kk vector sum
               if(c_rl(kk,ic)+xc(kk,ic).gt.0) then
                 alpha(kk) = ( c_rp(kk,ic)+c_rl(kk,ic))                 &
     &                            *xc(kk,ic)*c_h2oliq(kk)*avogadrl      &
     &              /(c_rp(kk,ic)+c_rl(kk,ic)                           &
     &                            +xc(kk,ic)*c_h2oliq(kk)*avogadrl)
                  oddhdel(kk,1) = oddhdel(kk,1)                         &
     &             - senhcat(kk,c_icat(ic)) * alpha(kk)
               end if
! kvec       end do                      ! kk vector sum
                             ! if(c_h2oliq(kk).gt.0) then
           end if

                                 ! if(ic.eq.c_npequil(ic)) then
         end if


! TEST WRITE
!          if(c_kkw.gt.0) write(c_out,11025) c_tchem(ic),xc(c_kkw,ic),
!    *       alpha(c_kkw), senhcat(c_kkw,c_icat(ic)),
!    *          oddhsum(c_kkw,1), oddhdel(c_kkw,1)
! 11025      format(/' PRIOR HX: XR  (RL*XR) SENHCAT ODDHSUM ODDHDEL =',
!    *  /,a8,2x,8(1pe10.3))

                  !  if((c_icat(ic).eq.3...)
        end if
                    !do ic=1,c_nchem2
      end do
!
! END : ADD PRIOR OH, HO2 TO ODDHSUM INCLUDING RO2
!
! REPEAT ADD PRIOR OH, HO2 WITH ODDHSUM-2, WITHOUT RO2

      do ic=1,c_nchem2

        if((c_icat(ic).eq.8.or.c_icat(ic).eq.9.or.c_icat(ic).eq.10 )    &
     &         .and.  .not.c_lsts(ic).and. .not.c_llump(ic))  then


         if(ic.eq.c_npequil(ic)) then
! kvec     do       kk=1,c_kmax       ! kk vector sum
            oddhsum(kk,2) = oddhsum(kk,2)                               &
     &                   +   c_xcin(kk,ic) - xc(kk,ic)



            alpha(kk)=0.
! kvec     end do                      ! kk vector sum
! kvec     do       kk=1,c_kmax       ! kk vector sum
            if(c_rl(kk,ic)+xc(kk,ic).gt.0) then
             alpha(kk) =  (c_rp(kk,ic)+c_rl(kk,ic))*xc(kk,ic)           &
     &           /(c_rp(kk,ic)+c_rl(kk,ic)+xc(kk,ic))

!   TEMPORARY 2005 BUG CHANGE!!!! 2005 -
!     SHOULDN'T oddhdel include PRIOR MINUS ANY SENSITIVITY????
!            alpha(kk) =  (xc(kk,ic)          )*xc(kk,ic)
!    *           /(c_rp(kk,ic)+c_rl(kk,ic)+xc(kk,ic))

             oddhdel(kk,2) = oddhdel(kk,2)                              &
     &             - senhcat(kk,c_icat(ic)) * alpha(kk)

! TEMPORARY DEBUG WRITE
!            if(c_kkw.gt.0) write(c_out, 11019)
!    *        c_tchem(ic),c_icat(ic), xc(c_kkw,ic)
!    *       ,   c_xcin(c_kkw,ic), alpha(c_kkw)
!    *       , senhcat(c_kkw,c_icat(ic)), oddhsum(c_kkw,2),
!    &          oddhdel(c_kkw,2)

            end if
! kvec     end do                      ! kk vector sum
                                 ! if(ic.eq.c_npequil(ic)) then
         else

           if(c_h2oliq(kk).gt.0) then
! kvec       do kk=1,c_kmax           ! kk vector sum
               oddhsum(kk,2) = oddhsum(kk,2)                            &
     &       + (  c_xcin(kk,ic) - xc(kk,ic)) *c_h2oliq(kk)*avogadrl
               alpha(kk)=0.
! kvec       end do                      ! kk vector sum
! kvec       do kk=1,c_kmax           ! kk vector sum
               if(c_rl(kk,ic)+xc(kk,ic).gt.0) then
                 alpha(kk) = ( c_rp(kk,ic)+c_rl(kk,ic))                 &
     &                            *xc(kk,ic)*c_h2oliq(kk)*avogadrl      &
     &              /(c_rp(kk,ic)+c_rl(kk,ic)                           &
     &                            +xc(kk,ic)*c_h2oliq(kk)*avogadrl)
                  oddhdel(kk,2) = oddhdel(kk,2)                         &
     &             - senhcat(kk,c_icat(ic)) * alpha(kk)
               end if
! kvec       end do                      ! kk vector sum
                             ! if(c_h2oliq(kk).gt.0) then
           end if

                                 ! if(ic.eq.c_npequil(ic)) then
         end if


! TEST WRITE
!          if(c_kkw.gt.0) write(c_out,11025) c_tchem(ic),xc(c_kkw,ic),
!    *       alpha(c_kkw), senhcat(c_kkw,c_icat(ic)),
!    *          oddhsum(c_kkw,2), oddhdel(c_kkw,2)

                  !  if((c_icat(ic).eq.3...)
        end if
                    !do ic=1,c_nchem2
      end do

! END REPEAT: ADD PRIOR OH, HO2 TO ODDHSUM

! (dHxdNOx*dNOxdOH IS CUT.  IT IS COUNTED THROUGH SENHCAT(NOX).)

! Add PRIOR OH, HO2 to oddhloh, oddhlho2
! 2009 CORRECTION: steady state control
! (ISSUE TO CHECK!)

          if(.not.c_lsts(ic1))  then
            do i=1,2
      do neq=1,(c_nequil(ic1)+1)
        ic=ic1
        if(neq.gt.1)ic=c_ncequil(ic1,(neq-1))
!       do  kk=1,c_kmax        ! kk vector loop
          alpha(kk) = 1.
          if(neq.gt.1) alpha(kk)= c_h2oliq(kk)*avogadrl
           oddhloh(kk,i) = oddhloh(kk,i) + xc(kk,ic)*alpha(kk)
!       end do                ! kk vector loop
                       ! neq-1,(c_nequil(ic1)+1)
      end do

      do neq=1,(c_nequil(ic2)+1)
        ic=ic2
        if(neq.gt.1)ic=c_ncequil(ic2,(neq-1))
!       do  kk=1,c_kmax        ! kk vector loop
          alpha(kk) = 1.
          if(neq.gt.1) alpha(kk)= c_h2oliq(kk)*avogadrl
           oddhlho2(kk,i) = oddhlho2(kk,i) + xc(kk,ic)*alpha(kk)
!       end do                ! kk vector loop
                       ! neq-1,(c_nequil(ic2)+1)
      end do
                         !do i=1,2
           end do
                                   !if(.not.c_lsts(ic1))  then
          end if


! ------------
!  END PRELIMINARY:  ADD PRIOR OH, HO2, RO2 INTO ODDHSUM, ODDHDEL
! ------------

! ------------
! CONVERGENCE TEST INDICES - SET TO PRIOR FOH, XOH.
! ------------
       xfohtest = foh(1)
       c_ohtest = xc(1,ic1)


! ------------
!  FOH = OH/HO2 RATIO
! ------------
!
! FOH=OH/HO2 RATIO.  THIS IS SPLIT INTO THREE COMPONENTS:
! FOH1A = OH SOURCE FROM HO2.  FOH1B=OTHER OH SOURCES
! FOH2 = OH SINKS.
! WHEN OH-HO2 EXCHANGE DOMINATES, OH/HO2 = FOH1A/FOH2.
! WHEN OTHER SOURCES DOMINATE, IT WORKS TO WEIGH FOH1B BY HO2 SINK/SRC.
!
! FROM OH BACK-EULER EQUATION: k2*HO2+Soh=kl*OH; FOH=k2/k1 + Soh/k2*HO2;
! -> FOH=FOHp*(FOH1a/FOH2 + FOH1b/(FOH2*xho2src/sink).

! NOTE:  USE XRP(KK,1) = OH PRIOR.  XRP(KK,3)=HO2 PRIOR.
! THESE WILL INCLUDE AQUEOUS EQUIVALENT SPECIES SUMS.
!
!  CHANGE 1195 - FOH1A, THE OH SOURCE FROM HO2, IS SUMMED
!  FROM A SPECIAL REACTION INDEX (NRFOH).
!
! CHANGE 1996
!  OH/HO2 IS ADJUSTED FROM PRIOR BASED ON RP/RL FOR OH, HO2
!  ALSO: DIFFICULT CONVERGENCE AID TO PROTECT AGAINST CRAZY HO2-H2O2
!  IN FIRST TIME STEP.
!    *** CHECK THAT THIS WORKS IN REMOTE TROP, OTHER ENVIRONMENTS.***
!         RP, RL SHOULD INCLUDE PRIOR OH, HO2 ALSO.

! 1996 ALTERNATIVE:   (GOES WITH 1996 WRITE, BELOW)
!      do kk=1,c_kmax             ! kk vector loop
         foh1(kk) = (xrp(kk,1)  / xrp(kk,3))
         foh(kk) = foh1(kk)                                             &
     &        * (rpro(kk,1)/rloss(kk,1) )                               &
     &        * (rloss(kk,3)/rpro(kk,3) )

! 1997 - ADD PROTECT AGAINST WILD SWINGS IN FOH.  (10x, then 50/50 avg.)

        if(foh(kk).gt.100.*foh1(kk)) foh(kk)=100.*foh1(kk)
        if(foh(kk).lt.0.01*foh1(kk)) foh(kk)=0.01*foh1(kk)
!      end do         ! kk vector loop


!  AUTOMATED DIFFICULT CONVERGENCE OPTION   (FEBRUARY 2005) :
!   SET GEOMETRIC MEAN vs PRIOR FOR CASES WITH DIFFICULT CONVERGENCE.
!   Set here for foh.   NOTE:  use OH to store FOH history.
!
       if(c_iter.ge.4) then
         call setgeom(ic1)
                           !if(c_iter.ge.4) then
       end if
!      do kk=1, c_kmax          ! kk vector loop
         foh(kk)     =(foh(kk)    **geomavg(kk,ic1) )                   &
     &                * (foh1(kk)    **(1.-geomavg(kk,ic1)) )
         history(kk,ic1,c_iter) = foh(kk)
!      end do                  ! kk vector loop



! FOHTEST = CONVERGENCE TEST FOR FOH. (ABOVE,PRIOR FOHTEST=PRIOR FOH.)
      xfohtest = abs(1.-foh( 1  ) /(xfohtest    +1.0e-08))

! -------------------
! ODD HYDROGEN BALANCE.
! -------------------
!     (A + B*OHp = ODDHSUM; A+B*OH=0; B*OHPp=ODDHDEL<0 )
! WITH ZERO PROTECT.  WARNING!  THIS HIDES A MULTITUDE OF (NIGHT) SINS.
!
! 1996 ADDITION:  OH, HO2 IS ADJUSTED
! SO THAT % CHANGE IN OH*HO2 IS CONSTANT.  (OH=OH*sqrt(foh/fohp))
!
!  2005 CHANGE:  OH, HO2 adjusted based on Hx losses attributed to OH vs
!  So that species responsible for losses changes closest to change in H
!  Equations:
!   Lho2*Fho2 + Loh*Foh = (Lho2+Loh )*Fh
!   OH/HO2 = (OHp/HO2p) * Fdroh      (Fdroh = FOH*HO2p/OHp)
!   => Foh*(Lho2/Fdroh + Loh) = (Lho2+Loh)*Fh
!    => Foh = (Lho2+Loh)*Fh/(Lho2/Fdroh+Loh)
!
! (2009 OPTION to set dHx/dOH based on iteration history - deleted.
!   algorithm description is in chemsolnotes)
!
! 2009 CHANGE:  ODDHFAC = weighted sum of two alternative oddh factors,
!   one with RO2 included and one WITHOUT RO2.
!   WEIGHTING: RATEK(no+ho2)*NO versus TIME  (r*NO/(r*NO + 1/time) sec-1
!    (= include RO2 when rapid conversion RO2 to HO2)
!
! 2009 CHANGE: This only works for NON-AQUEOUS.
!
!   ODDH WEIGHTING FACTOR

! kvec do kk=1,c_kmax         ! kk vector loop
        oddhro2f(kk) = 1.
! kvec end do                  ! kk vector loop
!      if(c_iter.gt.1) then
! kvec   do kk=1,c_kmax         ! kk vector loop
!         if(c_h2oliq(kk).eq.0.) then
!          oddhro2f(kk) = (ratek(kk,c_nrho2no)*xc(kk,c_nno))
           oddhro2f(kk) =2.* (ratek(kk,c_nrho2no)*xc(kk,c_nno))
           oddhro2f(kk) = oddhro2f(kk)/(oddhro2f(kk)+ 1.0/c_time)
!         end if
! kvec   end do                  ! kk vector loop
!      end if          !if(c_iter.gt.1) then

! TEMPORARY DEBUG WRITE (check RO2F formation)
!       if(c_kkw.gt.0) write(c_out,*) 'ODDHRO2F, nr, time rate = ',
!    &    oddhro2f(c_kkw), c_nrho2no, c_time
!    &     ,ratek(c_kkw,c_nrho2no)
!       if(c_kkw.gt.0) write(c_out,*) '          nc xc       e = ',
!    &     c_nno, xc(c_kkw, c_nno)

! kvec do kk=1,c_kmax          ! kk vector loop
        oddhfac1(kk) = 1.
        if(oddhdel(kk,1).ne.0) then
           oddhfac1(kk) = 1. - oddhsum(kk,1)/oddhdel(kk,1)
           if(oddhfac1(kk).le. 0.) oddhfac1(kk)= 0.2
        end if

        oddhfac2(kk) = 1.
        if(oddhdel(kk,2).ne.0) then
           oddhfac2(kk) = 1. - oddhsum(kk,2)/oddhdel(kk,2)
           if(oddhfac2(kk).le. 0.) oddhfac2(kk)= 0.2
        end if

        oddhfac(kk) = oddhro2f(kk)*oddhfac1(kk)                         &
     &      + (1.-oddhro2f(kk)) *oddhfac2(kk)
!       oddhfac(kk) = oddhfac1(kk)

!          xc(kk,ic1) = xrp(kk,1)*oddhfac(kk)   ! moved just below
!
! kvec   end do                  ! kk vector loop
!
! OHSOLVE DEBUG WRITE
!       if(c_kkw.gt.0) write(c_out,*) 'ODDHFAC1 = 1-ODDHSUM/ODDHDEL:',
!    &    oddhfac1(c_kkw), oddhsum(c_kkw,1), oddhdel(c_kkw,1)
!       if(c_kkw.gt.0) write(c_out,*) 'ODDHFAC2 = 1-ODDHSUM/ODDHDEL:',
!    &    oddhfac2(c_kkw), oddhsum(c_kkw,2), oddhdel(c_kkw,2)
!       if(c_kkw.gt.0) write(c_out,*) 'ODDHFAC, ODDHRO2F = ',
!    &    oddhfac(c_kkw), oddhro2f(c_kkw)

! ---------------
! 2009 OPTION to adjust dHx/dOH based on iter history was deleted from h
! ---------------

! --------------------------
! APPLY HX FACTOR TO OH, HO2
! --------------------------

! kvec do kk=1,c_kvec            ! kk vector loop
        xc(kk,ic1) = xrp(kk,1)*oddhfac(kk)

! TEMPORARY DEBUG WRITE
!       if(c_kkw.gt.0) write(43,*)' FIRST OH=',xc(c_kkw,ic1)

        if(foh(kk).ne.0) then

! 2005 OPTION
!  (2009 NOTE: what about steady state? Included in foh, added for oddhl
!     OK:  oddhloh represents loss of Hx linked to OH, not source (=OHin
!     Prior OH counts as loss in nonsteady state case only.)

!
        alpha(kk) = oddhfac1(kk)*oddhloh(kk,1)                          &
     &          +   oddhfac2(kk)*oddhloh(kk,2)
         beta(kk) = oddhfac1(kk)*oddhlho2(kk,1)                         &
     &          +   oddhfac2(kk)*oddhlho2(kk,2)
!       if(oddhloh(kk,2).gt.0.and.oddhlho2(kk,2).gt.0.) then
        if(alpha(kk)    .gt.0.and.beta(kk)      .gt.0.) then
         xc(kk,ic1) = xc(kk,ic1)*                                       &
     &       (oddhloh(kk,2) + oddhlho2(kk,2)) /                         &
     &         (oddhloh(kk,2)  + oddhlho2(kk,2)                         &
     &                         /(foh(kk)*xrp(kk,3)/xrp(kk,1)) )
                      !if(oddhloh(kk).gt.0.and.oddhlho2(kk).gt.0.) then
        else
         xc(kk,ic1) = xc(kk,ic1)*sqrt(foh(kk)*xrp(kk,3)/xrp(kk,1))
                      !if(oddhloh(kk).gt.0.and.oddhlho2(kk).gt.0.) then
        end if

! HO2
         xc(kk,ic2) = xc(kk,ic1)/foh(kk)
        end if
! kvec end do                     ! kk vector loop

! XOHTEST = CONVERGENCE TEST FOR OH.
!  Based on prior GAS+AQ SUM (XRP) vs NEWLY CALCULATED
!   = ratio of CHANGE (new-prior)/PRIOR OH
!   => NIGHTTIME OVERLY STRINGENT: night OH is very small;
!      better to use change vs RPRO, RLOSS. vs exact balance???

      c_ohtest = xrp(1,1)
      if(c_ohtest.eq.0.) c_ohtest = 1.0e-08
      c_ohtest = abs(1.-xc(1,ic1)  /(c_ohtest           ))

! TEMPORARY DEBUG TEST WRITE: c_ohtest
!     if(c_kkw.gt.0) write(c_out,*) 'CONVERGENCE: xrp, xc, ohtest=',
!    &      xrp(1,1), xc(1,ic1), c_ohtest

! 2009 CHANGE:  CONVERGENCE TEST = change in OH, HO2 vs RPRO-RLOSS
!      a1 =  rloss - rpro  (includes xc-xcin if non-steady-state)
!      a2 = max:  xc, (rpro+rloss)/2. 1e-8
!     test = abs(a1/a2)
!     test for OH, HO2, maximum

! CONVERGENCE TEST FOR OH
                                           !rloss, rpro already include
      alpha(1) = rloss(1,1) - rpro(1,1)
!     if(.not.c_lsts(ic1))
!    &      alpha(1) = alpha(1) + xc(1,ic1) - c_xcin(1,ic1)
      beta(1) = 0.5*(rloss(1,1)+rpro(1,1))
      if(xc(1,ic1).gt.beta(1)) beta(1)=xc(1,ic1)
      if(beta(1).le.0.) beta(1) = 1.0D-8
      c_ohtest = abs(alpha(1)/beta(1) )

! TEMPORARY DEBUG TEST WRITE: c_ohtest
!     if(c_kkw.gt.0) write(c_out,*)
!    &  'CONVERGENCE: rloss, rpro, xc, xcin,a,b, ohtest=',
!    &   rloss(1,1), rpro(1,1), xc(1,ic1), c_xcin(1,ic1),
!    &   alpha(1), beta(1), c_ohtest

! CONVERGENCE TEST FOR HO2 (note, rpro(1,3) for HO2)
                                         ! rloss, rpro include xc-xcin
      alpha(1) = rloss(1,3) - rpro(1,3)
!     if(.not.c_lsts(ic2))
!    &      alpha(1) = alpha(1) + xc(1,ic2) - c_xcin(1,ic2)
      beta(1) = 0.5*(rloss(1,3)+rpro(1,3))
      if(xc(1,ic2).gt.beta(1)) beta(1)=xc(1,ic2)
      if(beta(1).le.0.) beta(1) = 1.0D-8
      gamma(1) = abs(alpha(1)/beta(1) )
      if(gamma(1).gt.c_ohtest) c_ohtest = gamma(1)

! TEMPORARY DEBUG TEST WRITE: c_ohtest
!     if(c_kkw.gt.0) write(c_out,*)
!    &  'CONVERGENCE: rloss, rpro, xc, xcin,a,b, ohtest=',
!    &   rloss(1,3), rpro(1,3), xc(1,ic2), c_xcin(1,ic2),
!    &   alpha(1), beta(1), gamma(1)

! ADDED CONVERGENCE EXIT AT NIGHT:  IF XOH IS LOW AND NOX CONVERGES.
!  CUT

! DIFFICULT CONVERGENCE OPTION:  GEOMETRIC  AVERAGE WITH PRIOR OH, HO2.

!  AUTOMATED CONVERGENCE OPTION (FEBRUARY 2005):
!   SET GEOMETRIC MEAN BASED ON HISTORY (vs HARD-WIRED OPTION above)
!  HARD-WIRED OPTION:  cut call to setgeom
!
!   Set here for Hx.   Use HO2 to store Hx history.
!   For Hx, adjust based on Hx parameter 1.-oddhsum/oddhdel
!           and history is running product of adjustments
!
!   Note OPTION WITHIN AUTOMATED CONV (SETGEO):  delta vs ratio.

           if(c_iter.ge.4) then
             call setgeom(ic2)
                               !if(c_iter.ge.4) then
           end if
!          do kk=1, c_kmax          ! kk vector loop
             xc(kk,ic1) = (xc(kk,ic1)**geomavg(kk,ic2) )                &
     &                      *(xrp(kk,1)**(1.-geomavg(kk,ic2)) )
             xc(kk,ic2) = (xc(kk,ic2)**geomavg(kk,ic2)                  &
     &                      )*(xrp(kk,3)**(1.-geomavg(kk,ic2)) )
             history(kk,ic2,c_iter) = oddhfac(kk)
!            oddhfacp(kk) = oddhfac(kk)**geomavg(kk,ic2)
!          end do                  ! kk vector loop
           if(c_iter.gt.1) then
! 2009 CORRECTION: ics is error
!            do kk=1, c_kmax          ! kk vector loop
!              history(kk,ic2,c_iter) = history(kk,ics,c_iter)
!    *           * history(kk,ics,(c_iter-1))
               history(kk,ic2,c_iter) = history(kk,ic2,c_iter)          &
     &           * history(kk,ic2,(c_iter-1))
!            end do                  ! kk vector loop
                              !if(c_iter.gt.1) then
           end if

! POSSIBLE ADJUSTMENT HERE:
!   if history positive, and sqrt high vs oddhfac - make oddhfac higher?

! FEBRUARY 2005 CO3 HX ADJUSTMENT
!  ADJUST CO3 BY SAME ADJUSTMENT AS ODD-H.
!  WITH TEST TO MAKE SURE P(CO3) IS SIGNIFICANT

        ics = namechem('     CO3')
        if(ics.gt.0) then
!        do kk=1,c_kmax             ! kk vector loop
          alpha(kk) = 0.
!        end do                    ! kk vector loop
         do neq=1,(c_nequil(ics)+1)
          icc=ics
          if(neq.gt.1)icc=c_ncequil(ics,(neq-1))
!         do kk=1,c_kmax            ! kk vector loop
            alpha(kk) = alpha(kk) + c_rp(kk,icc)
!         end do                   ! kk vector loop
                          ! neq-1,(c_nequil(ics)+1)
         end do
         do neq=1,(c_nequil(ics)+1)
          icc=ics
          if(neq.gt.1)icc=c_ncequil(ics,(neq-1))
!         do kk=1,c_kmax            ! kk vector loop
           if(alpha(kk).ge.0.1*oddhsrc(kk,1)) then
!            xc(kk,icc) = xc(kk,icc) * (oddhfac(kk)**0.5)
             xc(kk,icc) = xc(kk,icc) * (oddhfac(kk)**geomavg(kk,ic2) )
                                !if(alpha(kk).ge.0.1*oddhsrc(kk)) then
           end if
!         end do                   ! kk vector loop
                          ! neq-1,(c_nequil(ics)+1)
         end do
                     !if(ics.gt.0) then
        end if


! -----------------------------------------------
! TEST WRITE FOR OH, HO2 AND FOH FOR THIS ITERATION.
! INCLUDING CALL TO OHWRITE FOR ODD HYDROGEN BALANCE

      if(c_kkw.gt.0) then

        write(c_out,1851) c_iter
 1851   format(//,' ITER =',i3)

        xrooh = 0.
        pansum = 0.
        xhno4 = 0.
        xco3 = 0.
        do 1850 ic=1,c_nchem2
         if(c_icat(ic).eq. 4) xrooh = xrooh + xc(c_kkw,ic)
         if(c_icat(ic).eq. 5) pansum=pansum + xc(c_kkw,ic)
         if(c_icat(ic).eq. 6) xhno4 = xhno4 + xc(c_kkw,ic)
         if(c_tchem(c_npequil(ic)).eq.'     CO3') then
           if(c_tchem(ic).eq.'     CO3') then
              xco3 = xco3+ xc(c_kkw,ic)
           else
              xco3 = xco3+ xc(c_kkw,ic)*c_h2oliq(kk)*avogadrl
           end if
         end if
 1850   continue

        write(c_out,1852)
 1852   format('ODD HYDROGEN:',//,                                      &
     &  '   OH       HO2      H2O2    H+ROOH     PAN     HNO3   ',      &
     &  '    CO3   FOH')

        if(oddhdel(c_kkw,1).eq.0.or.oddhdel(c_kkw,2).eq.0) then
         write(c_out, 1898)
 1898    format(/,' WARNING!  ODDHDEL=0.  OH UNCHANGED.')
        else
         if(oddhsum(c_kkw,1)/oddhdel(c_kkw,1).gt.1) write(c_out,1849)
         if(oddhsum(c_kkw,2)/oddhdel(c_kkw,2).gt.1) write(c_out,1849)
 1849     format(/,' WARNING!  OH<0, CORRECTED.')
        end if

        write(c_out,1899) xc(c_kkw,ic1),xc(c_kkw,ic2), xc(c_kkw,ic3),   &
     & xrooh, pansum, xc(c_kkw,6), xco3,foh(c_kkw)
!    * xrooh, pansum, xc(c_kkw,6),xhno4,foh(c_kkw)
 1899   format(8(1pe10.3))

      write(c_out,1902)
 1902 format(/,'   O3        NO2       NO     ',                        &
     & '   NO3       HNO3      PANs      HONO    HNO4  '        )


      pansum = 0.
      hnosum = 0.
      do 1910 ic=1,c_nchem2
       if(c_icat(ic).eq.5) pansum=pansum+xc(c_kkw,ic)
       if(c_icat(ic).eq.6) hnosum = hnosum+xc(c_kkw,ic)
 1910 continue

      write(c_out,1911) xc(c_kkw,c_no3      ),xc(c_kkw,c_nno2     )     &
     & ,xc(c_kkw,c_nno      ), xc(c_kkw,c_nno3     )                    &
     &     ,xc(c_kkw,c_nhno3    )                                       &
     & ,pansum,hnosum
 1911 format(8(1pe10.3))

! PRIOR OH:  NOTE, THIS GIVES OH FROM PREVIOUS TIME STEP
!   AFTER DIFFICULT CONVERGENCE CORRECTION.
        write(c_out,1853)
 1853   format(/'PRIOR OH     HO2    ODDHFAC   ',                       &
     &     '(ODDHFAC1  ODDHFAC2  ODDHRO2F)')
        write(c_out,1899) xrp(c_kkw,1),xrp(c_kkw,3), oddhfac(c_kkw)     &
     &              ,oddhfac1(c_kkw), oddhfac2(c_kkw),oddhro2f(c_kkw)


!       write(c_out,1853)
! 1853    format(/'PRIOR OH     HO2     ODDHSUM1   ODDHDEL1'
!    &            '  ODDHSUM2  ODDHDEL2  ODDHRO2F'  )
! c  *    '  (OH=prior*(1-sum/del)')
!       write(c_out,1899) xrp(c_kkw,1),xrp(c_kkw,3), oddhsum(c_kkw,1),
!    *    oddhdel(c_kkw,1), oddhsum(c_kkw,2), oddhdel(c_kkw,2)
!    &    ,oddhro2f(c_kkw)

! FOH WRITE FOR 1195 METHOD:
!       write(c_out,1854)
! c -> FOH=FOHp*(FOH1a/FOH2 + FOH1b/(FOH2*xho2src/sink).
! 1854    format(/,'FOH ANALYSIS:   (FOH1B=non-ho2 sources of OH)',/,
!    * '  _FOH   =  _FOHp  *(  (_RP9 /_RL9 )  + _FOH1b/rl9 *  (_RL10  ',
!    * '/ _RP10  -1) )')
!      fohp = xrp(c_kkw,1)/xrp(c_kkw,3)
!      write(c_out,1899) foh(c_kkw), fohp
!    *   , rpro(c_kkw,1),rloss(c_kkw,1),
!    *     foh1b(c_kkw),  rloss(c_kkw,3), rpro(c_kkw,3)

! FOH WRITE FOR 1996 METHOD:
       write(c_out, 1856)
 1856  format(/,'FOH ANALYSIS: ',/,                                     &
     & ' FOH   =   FOHp  *(RPRO(oh)/ RLOSS(oh))/(RPRO(ho2)/RLOSS(ho2))')
       write(c_out,1899) foh(c_kkw), foh1(c_kkw)                        &
     &  , rpro(c_kkw,1),rloss(c_kkw,1),                                 &
     &    rpro(c_kkw,3), rloss(c_kkw,3)

       write(c_out,1861) oddhloh(c_kkw,1), oddhlho2(c_kkw,1)
       write(c_out,1861) oddhloh(c_kkw,2), oddhlho2(c_kkw,2)
 1861  format(/,'  ODDHLOH, ODDHLHO2 = ',(2(1pe10.3)))

       write(c_out,1862) geomavg(c_kkw,ic1), geomavg(c_kkw, ic2)
 1862  format(/,'  GEOM AVG FACTOR FOR FOH, Hx = ', 2f10.4)

        if(c_kkw.gt.0) call ohwrite(c_kkw)

      end if

!  END WRITE FOR ODD-HYDROGEN.  BACK TO THE SOLUTION.
!  ----------------------------------------------------


! PARTITION OH AND HO2 BETWEEN GAS AND AQUEOUS-EQUILIBRIUM SPECIES
! AS IN CHEMSOLVE.  WATCH INDICES! FOR OH, XR(IC2) AND XRP(3).

         do 235 is=1,3
          icc = ic1
          if(is.eq.2) go to 235
          if(is.eq.3) icc=ic2

          if(icc.gt.0) then
            if(c_nequil(icc).gt.0) then

! AQUEOUS CONCENTRATIONS ARE UPDATED BY THE RATIO XR/XRP.
            do 240 neq=1,c_nequil(icc)
             ic = c_ncequil(icc,neq)
             if(ic.gt.0) then
!              do 15041 kk=1,c_kmax
                xc(kk,ic) = xc(kk,ic)                                   &
     &                    * xc(kk,icc)/xrp(kk,is)
15041          continue
             end if
  240       continue

! GAS-MASTER XR IS REDUCED BY AQUEOUS CONCENTRATIONS
!  WITH UNIT CONVERSION (AVOGADRL)
            do 242 neq=1,c_nequil(icc)
             ic = c_ncequil(icc,neq)
             if(ic.gt.0) then
!              do 15044 kk=1,c_kmax
                xc(kk,icc) = xc(kk,icc)                                 &
     &            - xc(kk,ic)*c_h2oliq(kk)*avogadrl
15044          continue
             end if
  242       continue

            end if
          end if
  235   continue

! ESTABLISH SENHCAT (=d lnXR/d lnOH) FOR ODD HYDROGEN SPECIES.
!  (SENHCAT IS USED TO RESOLVE HX = A+B*OH.  IN THE SUM,
!   ODDHSUM = + dHx; ODDHDEL = + dHx*SENHCAT =>B*OH.)

! FOR HO2:  dHO2/dOH from HO2 EQ:
!  kOH+otherSho2=k1HO2+2k2HO2**2 = 2RPh2o2 + other RLho2.
!   (NOTE:  THIS USES IC INDEX FOR HO2, H2O2.)

! (NOTE:  TECHNICALLY, d/dOH = d/dOH + d/dHO2 dHO2/dOH
!  + d/dNOx dNOx/dOH.  NORMALLY, d/dNOx IS USED ONLY FOR NOX SPECIES.
!  OLD PROBLEM:  PAN OSCILLATION.  Maybe solve this by adding
!   dRO2/dOH = dHO2/dOH + dRO2/dNOx dNOx/dOH = dHO2/dOH (1-dNOx/dOH)
!   where dNOx/dOH<0.  )
!
!  Possible error (bmaingtest).  Originally both HO2 and RO2 senhcat
!  were multiplied by RP/RP+XXO.  This term was first dropped for RO2.
!  Then after 'bmaingtest' it worked best to drop the term for HO2 and R
!
! 1996 - AQUEOUS CHANGE.  RL, RP IS SCREWED UP BY EXCORR WITH AQUEOUS.
! TO FIX - REPLACE RL, RP WITH RLOSS, (RPRO-XRP) = GAS+AQUEOUS SUM.
!  ALGORITHM:  SENHCAT = RLOSS(HO2)/(RLOSS(HO2) + 2 RP(H2O2))
!
! 2009 CORRECTION: rp(H2O2) includes other sources (ALK+O3), leads to er
! Trying an alternative:  oddhlho2/2. = rp(H2O2) from Hx...
!     but it also includes rp (ROOH).
!
! note - is not the maximum dln HO2/dln OH = 0.5, not 0? from HO2+HO2,
!   but less if other sources
!  -> it should be rp(HO2 from OH)/(*+rp(HO2 from other sources))
!    = rp(HO2)
!
! OPTION TO TRY: rp(HO2)*(1+RO2/HO2)/(+oddhsrc)?
!    rpHO2(1+oddhsrc2/oddhsrc)/(*+oddhsrc)  ?
! ALT: loh/(+(oddhsrc-2O3+hv)

! SUM GAS AND AQUEOUS:  RLOSS(HO2), RPRO(H2O2)
!     do 11053 kk=1,c_kmax
       alpha(kk) = c_rl(kk,ic2)
       beta(kk) = c_rp(kk,ic3)
11053 continue


      if(c_nequil(ic2).gt.0)       then
        do 252 neq=1,c_nequil(ic2)
         ic = c_ncequil(ic2,neq)
!          do 11055 kk=1,c_kmax
              alpha(kk) = alpha(kk) + c_rl(kk,ic)
11055      continue
  252   continue
      end if

      if(c_nequil(ic3).gt.0)       then
        do 253 neq=1,c_nequil(ic3)
         ic = c_ncequil(ic3,neq)
!          do 11056 kk=1,c_kmax
              beta(kk) = beta(kk) + c_rp(kk,ic)
11056      continue
  253   continue
      end if

! 2009 correction: beta (ph2o2) < alpha (lho2)
!    protects against pH2O2 from source other than HO2 (TERP+O3->0.02 H2
! kvec do kk=1,c_kmax   ! kvec
          if(beta(kk).gt.alpha(kk)) beta(kk) = alpha(kk)
!         if(beta(kk).gt.0.5*alpha(kk)) beta(kk) = 0.5*alpha(kk)
! kvec end do            ! kvec
!

! MAIN SENHCAT CALCULATION.
!     do 11063 kk=1,c_kmax

! 1996 VERSION
! 2005:  GEOM MEAN for DIFFICULT CONVERGENCE (HO2-MCO3-PAN oscillation)
        senhcat(kk,10) =  alpha(kk)                                     &
     &                /  (alpha(kk) +2.*beta(kk)  )
! OPTION w/o  GEOM MEAN
!       senhcat(kk,3) = senhcat(kk,10)
! OPTION with GEOM MEAN
        senhcat(kk,3) = (senhcat(kk,10)**0.5)*(senhcat(kk,3)**0.5)
        senhcat(kk,10) = senhcat(kk,3)

! OLDER HO2-RO2 SENHCAT ALGORITHMS
! PRIOR 1994 VERSION
!       senhcat(kk,10) =  c_rl(kk,ic2)
!    *                /  (c_rl(kk,ic2)+2.*c_rp(kk,ic3))
!       senhcat(kk,3) = senhcat(kk,10)

! OLDER HO2-RO2 SENHCAT ALGORITHMS
!       senhcat(kk,10) = (c_rp(kk,ic2)-  c_xcin(kk,ic2)) * c_rl(kk,ic2)
!    *          /(      c_rp(kk,ic2) * (c_rl(kk,ic2)+2.*c_rp(kk,ic3)) )
!       senhcat(kk,10) = (c_rp(kk,ic2)            ) * c_rl(kk,ic2)
!    *                /(     ( c_rp(kk,ic2)+  c_xcin(kk,ic2))
!    *                        * (c_rl(kk,ic2)+2.*c_rp(kk,ic3)) )
!       senhcat(kk, 3) =
!    *    c_rl(kk,ic2)    /(   (c_rl(kk,ic2)+2.*c_rp(kk,ic3)) )

! dRO2/dNOx OPTION
!    *     *(1.-senhcat(kk,12))

11063 continue

! SENHCAT FOR RO2, RCO3:  FOR NOW, SET EQUAL TO HO2.
! THE TRUE VALUE IS 1-fhp*(1-fhr)
! WHERE fhp=k(RO2+HO2)/c_rl(RO2); fhr=k(ROOH+OH)/c_rl(ROOH).
! AND FOR RCO3:  1 - (1-fpp)(fhp)(1-fhr)
! WHERE fpp=k(RCO3+HO2)/c_rl(RCO3); fhp, fhr as above.

! IF ROOH IS STEADY STATE, ITS SENHCAT IS EQUAL TO THAT FOR RO2.
! THIS REQUIRES THAT ROOH STEADY STATE IS THE SAME AS H2O2.
!   (PROBABLY DOESN'T WORK ANYWAY.... FOR ROOH STST REMOVE ROOH.)
      if(c_lsts(ic3)) then
!       do 11073 kk=1,c_kmax
         senhcat(kk,4) = senhcat(kk,3)
11073   continue
      end if


! ----------------------------------------------------------
! END OHSOLVE
 2000 return
      END
! ----------------------------------------------------------





      subroutine setgeom(ic)
!

! This calculates the geometric average factor (geomavg(kk,kc))
!    which is used to adjust concentrations as a  geom. avg. with prior.
!      ( XR = (XR**F)*(XRP**(1-F))
!
! The factor is set based on the HISTORY of the past 3 iterations.
! When XR oscillates, GEOMAVG gets lower towards minimum (0.5 or 0.1)
! When XR keeps increasing or decreasing, GEOMAVG moves towards 1.
!
! OPTION:  How strongly does GEOMAVG react to history?
! OPTION:  Set minimum value for GEOMAVG (geomin)
!           Currently set to 0.1 for slow, sure convergence.
!            (previously 0.5)
!
! Inputs:    Species number (ic)
!            history(kk,ic,c_iter)  - past iterative solutions
!            geomavg(kk,ic) - previous geometric avg factor.
!
!
! Outputs:  geomavg(kk,ic) = new geometric average factor for species.
!
!
! Called by:    quadchem
!
! Calls to:     chemsolve (to solve H2O2)
!               setgeom
!
! ---------------------------------------------
! History:
!  12/06 Written by Sandy Sillman from boxchemv7.f
!
! -------------------------------------------------------------------
!
! ----------------------------------------
      implicit none

! LOCAL VARIABLES
                               ! Minimum value for geo. avg. parameter
      double precision geomin

! ----------------------------------------
      kk=1

! LINE TO COMMENT OUT AUTOMATIC SETTING
!     if(c_iter.gt.0) return

! RETURN IF ITER < 4
      if(c_iter.lt.4) return
!
! OPTION:  SET MINIMUM VALUE FOR GEOMETRIC AVERAGE PARAMETER.
!   Originally set at 0.5, then 0.3.
!   Currently set at 0.1.  Low value insures slow, sure convergence.

      geomin = 0.1

! ESTABLISH TREND OVER PAST 3 ITERATIONS.
!  A = delta(last iter) / delta (previous iter)
!  OPTION:  A= [new/old ratio(last iter)] / [new/old ratio(previous iter
!     A<0:  oscillates.
!     A<-1:  oscillation getting worse
!     A>0:  monotone increase/decrease
!     A=> 0:  approaching convergence

!     do kk=1,c_kmax                ! kk vector loop
        alpha(kk) = 0.
        if(history(kk,ic,(c_iter-2)).ne.0.and.                          &
     &      history(kk,ic,(c_iter-3)).ne.0)  then
! DELTA OPTION
!         beta(kk) = history(kk,ic,(c_iter -1 ))
!    *              - history(kk,ic,(c_iter-2))
!         gamma(kk) = history(kk,ic,(c_iter-2))
!    *              - history(kk,ic,(c_iter-3))
! RATIO OPTION
          beta(kk) = history(kk,ic,(c_iter -1 ))                        &
     &               /history(kk,ic,(c_iter-2))  - 1.
          gamma(kk) = history(kk,ic,(c_iter-2))                         &
     &               /history(kk,ic,(c_iter-3))  - 1.

           alpha(kk) = beta(kk)/gamma(kk)
        end if
        if(alpha(kk).gt.1.) alpha(kk)= 1.
        if(alpha(kk).lt.-1.) alpha(kk)= -1.
!     end do                       ! kk vector loop

! DIFFICULT CONVERGENCE  OPTION:  MULTIPLY SETGEOM BY DAMPENING FACTOR.
!    Multiply by 1:  moves factor towards 1 or 0.5 instantly.
!    Multiply by 0.5 (standard):  moves factor more slowly.
!
!     do kk=1,c_kmax                ! kk vector loop
        alpha(kk) = alpha(kk) * 0.5
!     end do                       ! kk vector loop
!
! ADJUST GEOMETRIC AVERAGING FACTOR:
!   If A<0 (oscillating), move towards minimum (0.5)(0.1)(geomin)
!   If A>0 (steady trend),move towards maximum (1.)
!
!     do kk=1,c_kmax                ! kk vector loop
        if(alpha(kk).gt.0.2) then
          geomavg(kk,ic) = geomavg(kk,ic)                               &
     &       + alpha(kk)*(1.-geomavg(kk,ic))
        end if
        if(alpha(kk).lt.-0.2) then
          geomavg(kk,ic) = geomavg(kk,ic)                               &
     &       + alpha(kk)*(geomavg(kk,ic) - geomin)
        end if
!     end do                       ! kk vector loop

! TEST WRITE SETGEO
!     if(c_kkw.gt.0) then
!         write(c_out,101) ic, c_tchem(ic)
! 101       format (/,'GEOMAVG:  TEST IC = ', i4,2x,a8)
!         write(c_out,102) history(kk,ic,(c_iter-3)),
!    *       history(kk,ic,(c_iter-2)), history(kk,ic,(c_iter-1))
! 102       format(' HISTORY:  ', 3(1pe10.3))
!         write(c_out,103) alpha(c_kkw), geomavg(c_kkw,ic)
! 103       format (' ALPHA, GEOMAVG = ', 2(1pe10.3))
!     end if

! END GEOMAVG

 2000 return
      END
! ----------------------------------------





       subroutine presolve

!  This sets the initial value for six key species
!                        (OH, HO2,O3,NO,NO2,NO3, also H+)
!   based on NO-NO2-O3 equilibrium for NOx-Ox
!   and simple OH/HO2 ratio and jO3 for odd-h radicals.

!  The subroutine uses the following reactions:
!
!       #1:  NO2+hv->NO+O3          #2: NO+O3->NO2
!       #9:  O3+hv->2OH             #12: NO2+OH->HNO3
!       #16: OH+CO->HO2             #17: OH+O3->HO2
!       #18: HO2+NO->OH+NO2         #22: HO2+HO2->H2O2
!       #3:  NO2+O3->NO3
!  Also:
!       #17 OH+O3
!       #46 OH+CH4->HO2.
!
! The reactions are identified from "family" array:
!   family(1,i) = OH, HO2, H2O2
!   family(2,i) = O3, NO2, NO
!   family(3,i) = NO3, N2O5, HNO3
! These are used to identify reactions based on reactants.
!
! Initial  H+ is set to 1e-5.
!
! Inputs:    Initial species concentrations (c_xcin)
!            Chemical reactions
!            family array to ID reactions
!
! Outputs:   Estimated xc for OH, HO2, O3, NO, NO2, NO3, H+
!
!
! Called by:    quadchem
!
! Calls to:     None.
!
! ---------------------------------------------
! History:
!  12/06 Written by Sandy Sillman from boxchemv7.f
!
! -------------------------------------------------------------------
! ---------------------------------------------------------------
!
      implicit none

! LOCAL VARIABLES
       integer nspecial(40)
!                         (ic1,ic2,ic3,ic9,ic10 ic4)
!                         (O3  NO2 NO  OH  HO2  NO3)

       kk=1

! REACTION SUM:  IDENTIFY SPECIAL REACTIONS FOR HX, NOX
! AND SUM 'CRATE' (ALPHA) = OH+C REACTIONS.
! AND SUM GAMMA = NO3 LOSS REACTIONS.

       do 110 i=1,40
        nspecial(i) = 0
  110  continue
!      do 10036 kk=1,c_kmax
          alpha(kk) = 0.
          gamma(kk) = 0.
10036  continue

      do 10040 nr=1,c_nreac
! IDENTIFY SPECIAL REACTIONS BY REACTANT NUMBER
!       #1:  NO2+hv->NO+O3          #2: NO+O3->NO2
!       #9:  O3+hv->2OH             #12: NO2+OH->HNO3
!       #16: OH+CO->HO2             #17: OH+O3->HO2
!       #18: HO2+NO->OH+NO2         #22: HO2+HO2->H2O2
!       #3:  NO2+O3->NO3
       if(c_reactant(nr,1).eq.c_nno2.and.c_reactant(nr,2).eq.-1)        &
     &  nspecial(1)=nr
       if( (c_reactant(nr,1).eq.c_no3.and.c_reactant(nr,2).eq.c_nno)    &
     &  .or.(c_reactant(nr,1).eq.c_nno.and.c_reactant(nr,2).eq.c_no3) ) &
     &  nspecial(2)=nr
       if(c_reactant(nr,1).eq.c_no3.and.c_reactant(nr,2).eq.-1          &
     &     .and.c_product(nr,1).eq.c_noh)                               &
     &  nspecial(9)=nr
       if( (c_reactant(nr,1).eq.c_nno2.and.c_reactant(nr,2).eq.c_noh)   &
     &  .or.(c_reactant(nr,1).eq.c_noh.and.c_reactant(nr,2).eq.c_nno2) )&
     &  nspecial(12)=nr
       if( (c_reactant(nr,1).eq.c_nno.and.c_reactant(nr,2).eq.c_nho2)   &
     &  .or.(c_reactant(nr,1).eq.c_nho2.and.c_reactant(nr,2).eq.c_nno) )&
     &  nspecial(18)=nr
       if(c_reactant(nr,1).eq.c_nho2.and.c_reactant(nr,2).eq.c_nho2)    &
     &  nspecial(22)=nr
       if( (c_reactant(nr,1).eq.c_nno2.and.c_reactant(nr,2).eq.c_no3)   &
     &  .or.(c_reactant(nr,1).eq.c_no3.and.c_reactant(nr,2).eq.c_nno2) )&
     &  nspecial(3)=nr

! IDENTIFY OH+CO,HC OR O3 REACTIONS BY CATEGORY. SUM AS 'CRATE'(alpha).
       icat1 = 0
       icat2 = 0
       icr = 0
       if(c_reactant(nr,1).gt.0) then
         icat1 = c_icat(c_reactant(nr,1))
       end if
       if(c_reactant(nr,2).gt.0) then
         icat2 = c_icat(c_reactant(nr,2))
       end if
       if(icat1.eq.9.and.(icat2.eq.11.or.icat2.le.3))                   &
     &   icr = c_reactant(nr,2)
       if(icat2.eq.9.and.(icat1.eq.11.or.icat1.le.3))                   &
     &   icr = c_reactant(nr,1)

       if(icr.gt.0) then
!        do 10043 kk=1,c_kmax
            alpha(kk) =   alpha(kk)+ratek(kk,nr)*xc(kk,icr)

10043    continue
       end if

! IDENTIFY NO3 LOSS REACTIONS (gamma)
       icr = -1
       if(c_reactant(nr,1).eq.c_nno3) icr = c_reactant(nr,2)
       if(c_reactant(nr,2).eq.c_nno3) icr = c_reactant(nr,1)

       if(icr.gt.0) then
!        do 10045 kk=1,c_kmax
            gamma(kk) =   gamma(kk)+ratek(kk,nr)*xc(kk,icr)
10045    continue
       end if

       if(icr.eq.0) then
!        do 10046 kk=1,c_kmax
            gamma(kk) =   gamma(kk)+ratek(kk,nr)
10046    continue
       end if

10040 continue
!
! NOX:  A PRECISE INITIALIZATION WOULD SET EQUILIBRIUM BTWEEN NO+O3=NO2.
! EQUATION:  (NO)**2 + NO (Ox-NOx+j1/k2) - NOx j1/k2 = 0
! WHERE j1:  NO2+hv; k2: NO+O3.

              if(nspecial(1).gt.0.and.nspecial(2).gt.0) then
!       do 10033 kk=1,c_kmax
          beta(kk) = ratek(kk,nspecial(1))/ratek(kk,nspecial(2))
         xc(kk,c_nno)= 0.5*                                             &
     &             ( sqrt(  (  c_xcin(kk,c_no3) -   c_xcin(kk,c_nno)    &
     &                                            +  beta(kk) )**2      &
     &               + 4.* beta(kk)                                     &
     &               *(  c_xcin(kk,c_nno2)+  c_xcin(kk,c_nno))  )       &
     &               -( c_xcin(kk,c_no3)-  c_xcin(kk,c_nno)+ beta(kk)) )
         xc(kk,c_nno2) =                                                &
     &         c_xcin(kk,c_nno2)+  c_xcin(kk,c_nno)-xc(kk,c_nno)
         xc(kk,c_no3)=                                                  &
     &          c_xcin(kk,c_no3)+  c_xcin(kk,c_nno2)-xc(kk,c_nno2)

! ZERO-PROTECT SHOULD APPLY ONLY IF ERROR IN FORMULA.
         if(xc(kk,c_nno2).le.0) xc(kk,c_nno2)=0.1
         if(xc(kk,c_nno).le.0) xc(kk,c_nno)=0.1
         if(xc(kk,c_no3).le.0) xc(kk,c_no3)=0.1

10033   continue

! INITIAL NOX REDUCED BASED ON 5-HOUR LIFETIME
!  COMMENT OUT IF PRESET NOx OPTION)
        if(.not.c_lsts(c_nno2).and..not.c_lsts(c_nno)) then
!         do 10034 kk=1,c_kmax
           xc(kk,c_nno)= xc(kk,c_nno)/(1.+c_time/18000.)
           xc(kk,c_nno2) = xc(kk,c_nno2)/(1.+c_time/18000.)
10034     continue
        end if

             end if

! NO3:  PRELIMINARY VALUE SET FROM BACK-EULER FORMULA:
!  NO2+O3 SOURCE, ALL NO3 SINKS. (Added to deal with large-isop. crash.)

!       do 10053 kk=1,c_kmax
          xc(kk,c_nno3) =   c_xcin(kk,c_nno3)
10053   continue
        if(nspecial(3).gt.0) then
!         do 10054 kk=1,c_kmax
            xc(kk,c_nno3) = xc(kk,c_nno3)                               &
     &         +   ratek(kk,nspecial(3)) *xc(kk,c_no3)*xc(kk,c_nno2)
10054     continue
        end if
!       do 10055 kk=1,c_kmax
            xc(kk,c_nno3) = xc(kk,c_nno3)                               &
     &  / (1. + gamma(kk) )
10055   continue

! xno, xno2, xo3, xoh, xho2 - ALL CUT.
! oxno, oxno2, oxo3, rno, rno1, rno2, xnox - ALL CUT

! OH, HO2 INIITIALIZE:REQUIRES PRE-SET REACTION NUMBERS (see above)
!  PLUS AUTOMATED CRATE = #16, OH+CO, #17 OH+O3,#46 OH+CH4->HO2.
!  DECEMBER 1994:  CHANGE TO FULL QUADRATIC WITH PRIOR OH, HO2
!  AND PROTECT AGAINST NIGHTTIME STEADY STATE ZERO.  HO2 prior>1E6.

!     do 10079 kk=1,c_kmax
        foh(kk ) = 0.01
        if (ratek(kk ,nspecial(1)).ge.1.0E-03)                          &
     &    foh(kk )  = ratek(kk ,nspecial(18))                           &
     &                     *xc(kk ,c_nno) /  alpha(kk )

! FULL QUADRATIC SOLVE WITH PRIOR OH, HO2
        gamma(kk ) = 2.*c_time*ratek(kk ,nspecial(9))*xc(kk ,c_no3)     &
     &           +  c_xcin(kk,c_noh)+  c_xcin(kk,c_nho2)
        if(gamma(kk ).lt.1.01E+04) then
            c_xcin(kk,c_nho2) =   c_xcin(kk,c_nho2)+1.0E+04
            c_xcin(kk,c_noh) =   c_xcin(kk,c_noh) + 1.0E+02
          gamma(kk ) = gamma(kk ) + 1.01E+04
        end if

        beta(kk ) = 1. + 1./foh(kk ) +                                  &
     &                c_time*ratek(kk ,nspecial(12)) *xc(kk ,c_nno2)
        alpha(kk ) =  c_time* ratek(kk  ,nspecial(22))/(foh(kk )**2)

        if(alpha(kk )*gamma(kk ).lt.beta(kk)**2) then
          xc(kk,c_noh) = gamma(kk)/beta(kk)
        else
          xc(kk,c_noh) = (sqrt(beta(kk )**2 + 4.*alpha(kk )*gamma(kk ) )&
     &    - beta(kk )  )/(2.*alpha(kk ))
        end if


        xc(kk,c_nho2) = xc(kk,c_noh)/foh(kk)
10079           continue

! WRITE PRELIMINARY CONCENTRATIONS.  (PERMANENT)
!    (Add parameters if needed. CRATE is new and suspect.)

      if(c_kkw.gt.0) then
         write(c_out,1011) xc(c_kkw,c_noh),xc(c_kkw,c_nho2)             &
     &     ,  xc(c_kkw,c_nno), xc(c_kkw,c_nno2) ,xc(c_kkw,c_no3)        &
     &     , xc(c_kkw,c_nno3)
 1011    format(/' PRELIM oh,ho2,no,no2,o3,no3=',6(1pe10.3))

! TEST WRITE
!        xx1 = 2.*c_time*ratek(c_kkw,nspecial(9))*xc(c_kkw,c_no3)
!        write(c_out,1012) xx1,   c_xcin(c_kkw,c_noh),  c_xcin(c_kkw,c_n
! 1012     format(/,' HX SOURCES:  O3+hv   PRIOR OH   PRIOR HO2', /,
!    *       10x,5(1pe10.3))

!        xx2 = c_time*ratek(c_kkw,nspecial(22))
!        xx3 = c_time*ratek(c_kkw,nspecial(12))*xc(c_kkw,c_nno2)
!        write(c_out,1013) xx2,xx3
! 1013     format(/,'SINK FACTORS:',/,
!    *    ' OH=QUADRATIC(sources,1+1/foh+rHNO3,rH2O2)'
!    *    ,/,'rH2O2=',(1pe10.3),'  rHNO3=',(1pe10.3))
!        write(c_out,1021)  ratek(c_kkw ,nspecial(1)) ,
!    *                    ratek(c_kkw,nspecial(18)), foh(c_kkw)
! 1021     format(/,'FOH=RK18*NO/(RK*CO,HC) (if RK1>0.001).  '
!    *     /,'RK1, RK18, FOH=',3(1pe10.3))
! END TEST WRITE

      end if

! INITIAL CONCENTRATION FOR H+
! --------------------------
      if(c_aqueous(1,2).gt.0) then
!       do 10082 kk=1,c_kmax
          xc(kk,c_aqueous(1,2)) = 1.0E-05
          xc(kk,c_aqueous(1,3)) = 1.0E-09
10082   continue
      end if

! --------------------------
! END INITIALIZATION ROUTINE
! END PRESOLVE
 2000 return
      END
! ---------------------------------------------------------------





      subroutine prelump
!               (prechem)

! This sets initial concentrations for 'lumped' species.
! And sets other initial values  for the start of the chemistry solver
!  ('prechem').
!
! For lumped species:  It converts lumped sum and partition fractions
!    into concentrations for individual species.
!    and sets the input concentration (c_xcin) for lumped species.
!
! For all species:  it enters the input concentration (c_xcin) as xc.
!
! It  sets aqueous species to zero.
!   (Assumes that the saved values and initial concentrations
!     represent gas+aqueous sum for the gas-master species;
!     output aqueous concentrations are for information only.)
!
! It  sets zero initial values for running sums
!   (production, loss - RP, RL)
!
! It sets initial value for geometric average.
! it sets initial value for xcfinr (FINAL/AVG RATIO)
!
! OPTION:  SET XR=0.1 FOR ALL STEADY-STATE SPECIES?
! HOWEVER, IF A SPECIES IS SET IN STEADY STATE VS EMISSIONS,
! (e.g. ISOPRENE) THEN THIS SHOULD BE OVERRIDDEN.

! OPTION:  SET XR=0 FOR ALL UNPARTITIONED LUMPED SPECIES (RCO3-RPAN)
! SO THAT RP() IN MIDLUMP SETS PARTITIONING CORRECTLY
!
! Inputs:    Initial species concentrations (c_xcin)
!
! Outputs:   Working species concentrations (xc)
!            Initial species concentrations for lumped sp. (as c_xcin)
!            Initial zero values  for production, loss (rp, rl)
!            Initial geomavg
!
!
! Called by:    quadchem
!
! Calls to:     None.
!
! ---------------------------------------------
! History:
!  12/06 Written by Sandy Sillman from boxchemv7.f
!
! -------------------------------------------------------------------
! ----------------------------------------------------
      implicit none


       kk=1

! SET H2O CONCENTRATION IN CHEMISTRY ARRAY FROM INPUT VARIABLE
      if(c_nh2o.gt.0) then
! vec                      do kk=1,c_kvec
       xc( kk ,c_nh2o) = c_h2ogas(kk)
! vec                      end do ! do kk=1,c_kvec
                             !if(c_nh2o.gt.0) then
      end if
!


!  SET XC=XCIN, ZERO PROTECT,  AND MAYBE XC=0.1 FOR STEADY STATE.
!  FOR ALL TRANSPORTED SPECIES.
!
      do 1010 ic=1,c_nchem1

!              do 10009 kk=1,c_kmax
! vec                         do kk=1,c_kmax

! possible error with this and other ZERO PROTECT?
! 2004 fix - insures no descent to zero->NaN.

                 if(c_xcin(kk,ic).le.0.000001) c_xcin(kk,ic) = 0.000001
                 xc(kk,ic) = c_xcin(kk,ic)
! vec                        end do ! do kk=1,c_kmax

! SET XR=0.1 AND XXO=0. FOR STEADY-STATE.
!  XXO MUST BE ZERO, ELSE TROUBLE WHEN RP, RL=0.
!  THIS IS THE LINE TO COMMENT OUT, MAYBE.
        if(c_lsts(ic)) then
!               do 10006 kk=1,c_kmax
                 xc( kk ,ic)=0.1
                   c_xcin(kk,ic) = 0.
                   c_xcemit(kk,ic) = 0.
10006           continue
        end if


 1010  continue
! ----------------------
! LUMPED SPECIES ARE IDENTIFIED FROM ARRAY LUMP(I,J)
! READ FROM REACTION.DAT

       do 100 i=1,c_cdim
        ics = c_lump(i,1)
        if(ics.eq.0) go to 101

        ic1 = c_lump(i,2)
        ic2 = c_lump(i,3)

! SUM PARTITION FRACTIONS AND CORRECT IF ZERO.
! IF PRIOR PARTITION FRACTIONS ARE NOT SAVED: INITIAL XR SHOULD BE ZERO.
! ORIGINAL OPTION:  SET PARTITION = 100% FIRST SPECIES (IC1)
! AND CORRECT AT MIDLUMP BASED ON RP.  PROBLEM:  RCO3-RPAN.

! ALTERNATIVE OPTION: LEAVE PARTITIONED XR=0 AND CORRECT AT MIDLUMP.
! TO IMPLEMENT, SEE 'LUMPED SPECIES' BELOW.

!         do 16101 kk=1,c_kmax
           alpha(kk) = 0.
16101     continue
        do 120 ic=ic1,ic2
!         do 16104 kk=1,c_kmax
           alpha(kk) = alpha(kk) + xc(kk,ic)
16104     continue
  120   continue
!        do 16107 kk=1,c_kmax
           if(alpha(kk).eq.0) then
            xc(kk,ic1) = 1.
            alpha(kk) = 1.
           end if
16107    continue

! CONVERT PARTITION FRACTIONS INTO CONCENTRATIONS. ALSO ENTER XXO.
! ALSO ZERO-PROTECT AND ENTER XXO.
         do 130 ic=ic1,ic2
          c_lsts(ic) = c_lsts(ics)
!          do 16111 kk=1,c_kmax

! ORIGINAL VERSION - SET LUMPED SPECIES HERE.
!            xc(kk,ic) = xc(kk,ic)*xc(kk,ics)/alpha(kk)
!            if(xc(kk,ic).le.0.1) xc(kk,ic) = 0.1
! ALTERNATIVE OPTION:  SET LUMPED SPECIES = 0. FOR FIRST ITERATION;
!          THEN RESET BASED ON RP IN MIDLUMP.
             xc(kk,ic) = 0.1

! PUT LUMPED VALUES IN xcin
               c_xcin(kk,ic) = xc(kk,ic)
16111      continue
  130     continue

! SET EMISSIONS TO BE LESS THAN INPUT CONCENTRATION
!   (Input concentration includes emissions;
!      emissions are only used for timing in expo decay solution)

          do ic=1,c_nchem2

! v         do kk=1,c_kmax
               if (c_xcemit(kk,ic).gt.0.99*c_xcin(kk,ic))               &
     &                    c_xcemit(kk,ic)=0.99*c_xcin(kk,ic)
! v         end do ! do kk=1,c_kmax
                                 !do ic=1,nchem2
          end do

! WRITE PRELUMP (PERMANENT)
        if(c_kkw.gt.0) write(c_out,131) c_tchem(ic1),c_tchem(ic2),      &
     &    (xc(c_kkw,ic),ic=ic1,ic2)
  131  format(/,' TEST PRELUMP XR:  IC1-2= ',a8,2x,a8,/,(8(1pe10.3)))

  100  continue
  101  continue

! SET AQUEOUS CONCENTRATIONS EQUAL TO ZERO
       do 150 nrh=1,c_nreach
        icc=c_henry(nrh,1)
        if(icc.gt.0) then
          if(c_nequil(icc).gt.0)       then
            do 155 neq=1,c_nequil(icc)
             ic=c_ncequil(icc,neq)
!            do 16121 kk=1,c_kmax
              xc(kk,ic)=0.
16121        continue
  155       continue
          end if
        end if
  150  continue

! ZERO REACTION RATES (RR) TO PREVENT CARRY-OVER FROM PREVIOUS RUN.
       do 160 nr=1,c_nreac
!       do 16122 kk=1,c_kmax
         c_rr(kk,nr) = 0.
16122   continue
  160  continue
!
! ZERO RP, RL, RRP, RRL TO PREVENT CARRY-OVER FROM PREVIOUS RUN
!         (does not zero RRP, RRL before each iteration, only at start)
!
      do ic=1,c_nchem2
!       do kk=1,c_kmax      ! kk vector loop
         c_rp( kk ,ic) = 0.
         c_rl( kk ,ic) = 0.
         rrp( kk ,ic) = 0.
         rrl( kk ,ic) = 0.
         rppair(kk,ic) = 0.
         rlpair(kk,ic) = 0.
!       end do             ! kk vector loop
                      !do ic=1,c_nchem2
      end do

! TEST AND CORRECT RAINOUT PARAMETER (0<=rainfr<1)

!       do kk=1,c_kmax      ! kk vector loop
            if(c_rainfr(kk).lt.0)  c_rainfr(kk)=0.
            if(c_rainfr(kk).gt.0.9999)c_rainfr(kk)=0.9999
!       end do             ! kk vector loop
!
! SET DIFFICULT CONVERGENCE PARAMETER - INITIAL VALUES
!   Normally set to 1 for all except odd hydrogen.
!   Odd hydrogen:  HO2 (=Hxsum) factor set to 0.7
!                  OH  (=FOH)   factor set to 1.

      do ic=1,c_nchem2
!       do kk=1, c_kmax          ! kk vector loop
          geomavg(kk,ic) = 1.
!       end do                  ! kk vector loop
      end do

! HO2  (ic = namechem('     HO2') or c_nho2     )
      ic  =c_nho2
!     do kk=1, c_kmax          ! kk vector loop
          geomavg(kk,ic) = 0.7
!     end do                  ! kk vector loop

! OH   (ic = namechem('      OH') or c_noh      )
      ic  =c_noh
!     do kk=1, c_kmax          ! kk vector loop
          geomavg(kk,ic) = 1.0
!     end do                  ! kk vector loop
!
! Set ratio of FINAL to AVERAGE species concentrations (xcfinr)
!   This ratio is always ONE for back-Euler solution.
!   It is set to a different value when the EXPO DECAY solution is used.

      do ic=1,c_nchem2
!       do kk=1, c_kmax          ! kk vector loop
          xcfinr(kk,ic) = 1.0
!       end do                  ! kk vector loop
      end do
!
!  END PRELUMP
 2000 return
      END
! -------------------------------------
!

!
      subroutine midlump

! This re-sets the initial concentrations (c_xcin) for lumped species
!  based on calculated chemical production and loss.
!
! Initial input for lumped species consists of the lumped sum only.
! The partitioning of the sum into individual species
!  is assumed to be in proportion to chemical production.
!
! As production rates are iteratively calculated,
!   the assumed initial concentration of lumped species is adjusted.
!
! This is called at the start of each iteration (except #1).
! It adjusts the concentration at the start of the time step (c_xcin)
!   ,not the solution for the end of the time step (xc).
!
! 2006 MODIFICATION - SUM LUMPED GAS-PHASE SPECIES INTO XC
!   FOR USE IN REACTION RATES.
!
! 2008 LUMP OPTION: partition initial concentrations based on rp/(1+rl)
!      rather than rp (to avoid major error if lumped species are
!      chemically different - THEY SHOULD NOT BE DIFFERENT.
!
!
! Inputs:    Initial species concentrations (xc)
!
! Outputs:   Modified initial concentrations for lumped species (c_xcin)
!            Sums for lumped species (xc)
!
!
! Called by:    quadchem
!
! Calls to:     None.
!
! ---------------------------------------------
! History:
!  12/06 Written by Sandy Sillman from boxchemv7.f
!
! -------------------------------------------------------------------
!
! ----------------------

      implicit none

       kk=1

! LUMPED SPECIES ARE IDENTIFIED FROM ARRAY LUMP(I,J)
! ICS = ACCUMULATOR; IC1-IC2 ARE INDIVIDUAL SPECIES.

       do 100 i=1,c_cdim
        ics = c_lump(i,1)
        if(ics.eq.0) go to 101

        ic1 = c_lump(i,2)
        ic2 = c_lump(i,3)

! SUM LUMPED SPECIES (IC1-IC2) INTO ACCUMULATOR (ICS)
!   (for use in rate calculations)
!         do  kk=1,c_kmax
          xc(kk,ics) = 0.
!         end do
        do  ic=ic1,ic2
!         do kk=1,c_kmax
           xc(kk,ics) = xc(kk,ics) + xc(kk,ic)
!         end do
        end do

! SUM PARTITION CHEM. PRODUCTION RATES
!         do 16101 kk=1,c_kmax
          alpha(kk) = 0.
16101     continue
        do 120 ic=ic1,ic2
!         do 16104 kk=1,c_kmax
! 2006 ORIGINAL
           alpha(kk) = alpha(kk) + c_rp(kk,ic)
! 2008 LUMP OPTION
!          alpha(kk) = alpha(kk) + c_rp(kk,ic)/(1.+c_rl(kk,ic))
! END OPTION
16104     continue
  120   continue

! MODIFY XXO FOR PARTITIONED SPECIES BASED ON PARTITIONING OF
!  CHEM PRODUCTION.
! OCTOBER 1998 CORRECTION - XXO only.  XR would require POSTLUMP
!  SUM OF LUMPED SPECIES AND GAS+AQUEOUS.

        do 130 ic=ic1,ic2
!        do 16107 kk=1,c_kmax
           if(alpha(kk).gt.0) then
! 2006 ORIGINAL
              c_xcin(kk,ic) =   c_xcin(kk,ics)*c_rp(kk,ic)/alpha(kk)
! 2008 LUMP OPTION
!             c_xcin(kk,ic) =   c_xcin(kk,ics)*(
!    &          (c_rp(kk,ic)/(1.+c_rl(kk,ic)) ) /alpha(kk) )
! END OPTION
            if(  c_xcin(kk,ic).le.0)   c_xcin(kk,ic) = 0.1
           end if
16107    continue
  130   continue

! WRITE MIDLUMP (PERMANENT)
        if(c_kkw.gt.0) write(c_out,131) c_tchem(ic1),c_tchem(ic2),      &
     &    (  c_xcin(c_kkw,ic),ic=ic1,ic2)
  131  format(/,' TEST MIDLUMP XXO:  IC1-2= ',a8,2x,a8,/,(8(1pe10.3)))
        if(c_kkw.gt.0) write(c_out,132) c_tchem(ic1),c_tchem(ic2),      &
     &    (xc(c_kkw,ic),ic=ic1,ic2)
  132  format(/,' TEST MIDLUMP XR:  IC1-2= ',a8,2x,a8,/,(8(1pe10.3)))
!
! END LUMPED-SPECIES LOOP
  100 continue
  101 continue
!
!
!  END MIDLUMP
 2000 return
      END
! -------------------------------------




      subroutine postlump
!
! This calculates the final output species concentration (c_xcout)
!  from the working concentration (xc) (average over time step).
!  It also preserves the average species concentrations (c_xcav)
!  and the FINAL/AVERAGE ratio (xcfinr).
!
! It also  calculates sums for all 'lumped' species
!  at the end of the chemistry solution, and saves them in xc.
!
! This also sums aqueous equilibrium species
!  into a combined gas+aqueous value (in gas-phase units, molec/cm3)
!  which is saved as the gas-master species concentration.
!
! Aqueous concentrations are saved as output (in aqueous M/liter),
!   but it is assumed that these are not transported from step to step.
!   The gas-aqueous partitioning would also change with LWC.
!
! Partition fractions for individual lumped species
!   (as fraction of the lumped sum) are also saved for output.
!
! RAINOUT:  The sum of aqueous species into the gas-master
!   includes removal through rainout, based on the parameter RAINFR.
!
! WET DEPOSITION is calculated and saved for each aqueous species,
!   but it can be calculated more easily by using the output
!   concentrations of aqueous species (in M/L) and the rainfall rate.

!    (in gas-phase units).
! Here, this is omitted. Wet deposition can be derived instead
!  from the average concentrations of aqueous species (xcav, M/L)
!  multiplied by the  rain volume (liters) equivalent to rainfr
!  (=c_rainfr * c_h2oliq (kg/L) * alt. thickness (m) * 10 (dm/m))


!
!
! Inputs:    Average species concentrations (xc),
!              FINAL/AVERAGE ratio (xcfinr)
!              final spec ratio (xcf)
!
! Outputs:   Modified species concentrations (xc)
!            Final species concentrations (c_xcout)
!            Wet deposition:  c_xcwdep
!
!
! Called by:    quadchem
!
! Calls to:     None.
!
! ---------------------------------------------
! History:
!  12/06 Written by Sandy Sillman from boxchemv7.f
!
! -------------------------------------------------------------------

! ------------------------------------
      implicit none
       kk=1
!
!   WRITE FINAL SPECIES CONCENTRATIONS TO OUTPUT ARRAY:
!    final conc. (xcout) = avg concentration (xc) * ratio (xcfinr)
!     where ratio is always for gas-master species
!    average concentrations also entered into output array (xcav)
!
      do ic=1,c_nchem2
        ic1 = c_npequil(ic)
! v                                do kk=1,c_kmax
        c_xcav (kk,ic) = xc(kk,ic)
        c_xcout(kk,ic) = xc(kk,ic) * xcfinr(kk, ic1)
! v                                end do !do kk=1,c_kmax
                         !do ic=1,nchem2
      end do
!
!  AQUEOUS SPECIES:
!        SUM AQUEOUS SPECIES INTO GAS-MASTER SUM (in GAS UNITS)
!       (Individual aqueous species, aqueous units, are preserved,
!          but the gas-aq sum is the main output)

       do ic=1,c_nchem2
!
!    AQUEOUS SPECIES identified by npequil (pointer, aq-to-gas)
        ic1 = c_npequil(ic)
        if(ic1.ne.ic) then

! v                                do kk=1,c_kmax
           alpha(kk) = c_xcav(kk,ic)*c_h2oliq(kk)*avogadrl
           c_xcav (kk,ic1) = c_xcav(kk,ic1) + alpha(kk)
           c_xcout(kk,ic1) = c_xcout(kk,ic1)                            &
     &                     + alpha(kk)*xcfinr(kk,ic)
!
! v                                end do !do kk=1,c_kmax
         end if

                     !do ic=1,c_nchem2
       end do
!

! ------------------------------------
! LUMPED SPECIES ARE IDENTIFIED FROM ARRAY LUMP(I,J)
! READ FROM REACTION.DAT

       do 100 i=1,c_cdim
        ics = c_lump(i,1)
        if(ics.eq.0) go to 101

        ic1 = c_lump(i,2)
        ic2 = c_lump(i,3)

! SUM LUMPED SPECIES (IC1-IC2) INTO ACCUMULATOR (ICS)
! OPTION - INCLUDE RP, RL, PRODUCTION AND LOSS
!         do 16111 kk=1,c_kmax
          c_xcout(kk,ics) = 0.
          c_rp(kk,ics) = 0.
          c_rl(kk,ics) = 0.
16111     continue
        do 120 ic=ic1,ic2
!         do 16114 kk=1,c_kmax
           c_xcout(kk,ics) = c_xcout(kk,ics) + c_xcout(kk,ic)
           c_rp(kk,ics) = c_rp(kk,ics) + c_rp(kk,ic)
           c_rl(kk,ics) = c_rl(kk,ics) + c_rl(kk,ic)
16114     continue
  120   continue

! OPTION:  CONVERT LUMPED SPECIES VALUES (IC1-IC2) INTO PARTITION FR.
        do 130 ic=ic1,ic2
!        do 16107 kk=1,c_kmax
         kk=1
         if(c_kkw.gt.0) kk=c_kkw
           if(c_xcout(kk,ics).gt.0) then
!           c_xcout(kk,ic) = c_xcout(kk,ic)/c_xcout(kk,ics)
           end if
16107    continue
  130   continue

  100 continue
  101  continue

!
!  END POSTLUMP
 2000 return
      END
! -------------------------------------




!
      subroutine setro2

! This sets reaction rates for parameterized RO2-RO2 reactions
!  as described in the CBM-Z mechanism (Zaveri, JGR, 1998)
!
! The parameterization represents an ensemble of reactions
!     RO2i + RO2j -> PRODi + PRODj   (rate constant kij)
! These are represented by reactions
!     RO2i -> PRODi
!  with pseudo-1st-order rate constant equal to
!     kii*[RO2i] +  sum over j (kij*[RO2j])
!
!  (the self-reaction RO2i+RO2i is represented with a rate 2*kii
!   because it removes 2 RO2i and produces 2 PRODi)
!
! Rate constants kii are equal to ratero2(kk,ni,1) from chemrates.
! Rate constants kij = 2*sqrt(Ki*Kj) (from Zaveri, 1998)
!  where Ki and Kj are partial rate coefficients from RO2i and RO2j (i /
!  (ratero2(kk,ni,2) = sqrt(Ki))
!
! Rate constants are calculated using [RO2] from prior iteration
!  or initial estimate.
! For steady state and iter=1 only, assume that [RO2]=[HO2]/nnro2
!  (self-reaction only;  zero for cross-reactions)
!  otherwise  1st iter RO2 prior estimate = 0.
!
! The parameterized RO2 reaction also is identified as a self-reaction
!   in chemsolve.
!
! Note OPTION: double sensitivity to OH for PARAMETERIZED RO2
!              (see c_nrk(nr).eq.-13)
!
! ----------------------
!
! Inputs:    Prior species concentrations (from previous iter) (xc)
!            RO2 reaction list (nrro2)
!            and RO2 partial rate constants (ratero2)
!
! Outputs:   Rate constants (ratek) for parameterized RO2 reactions
!            Sums for lumped species (xc)
!
! Called by:    quadchem
!
! Calls to:     None.
!
! ---------------------------------------------
! History:
!   6/09 Written by Sandy Sillman based on Zaveri, cbmz.f
!
! -------------------------------------------------------------------
!
! ----------------------

      implicit none

      if(c_nnrro2.eq.0) return

       kk=1

! LOOP FOR PARAMETERIZED RO2 REACTIONS
       do  i=1,c_nnrro2
         nr = c_nrro2(i)
         ic  = c_reactant(nr ,1)

! SELF REACTION: Use [HO2] if stst and 1st iter, otherwise use [RO2]
!   stst 1st iter, estimate counts self-reaction rate, not summed RO2
!   and assumes summed RO2 = HO2 or HO2/2
!
         if(c_lsts(ic).and.c_iter.eq.1) then
! vec      do kk=1,c_kvec   ! kvec
!            alpha(kk) = xc(kk,c_nho2)/float(c_nnrro2)
             alpha(kk) = xc(kk,c_nho2)/(0.5*float(c_nnrro2))
!            alpha(kk) = xc(kk,c_nho2)/2.
! vec      end do            ! kvec
         else
! vec      do kk=1,c_kvec   ! kvec
             alpha(kk) = xc(kk,ic)
! vec      end do            ! kvec
                        !if(c_lsts(i).and.iter.eq.1) then
         end if

! PSEUDO-RATE CONSTANT FOR RO2-RO2 SELF-REACTION
!   (Doubled so that RO2->PROD parameterized reaction represents RO2+RO2
! vec      do kk=1,c_kvec   ! kvec
             ratek(kk,nr) = 2.*ratero2(kk, i,1)* alpha(kk)
! vec      end do            ! kvec

! LOOP TO ADD RO2-RO2 CROSS REACTIONS
          do j=1,c_nnrro2
            if(i.ne.j) then
              nr1 = c_nrro2(j)
              ic1 = c_reactant(nr1,1)

! RO2i+RO2j RATE CONSTANT = 2*sqrt(RKi*RKj),  ratero2(kk,i,2) = sqrt(RKi
! vec         do kk=1,c_kvec   ! kvec
                ratek(kk,nr)=ratek(kk,nr)                               &
     &           + 2.*ratero2(kk, i,2)*ratero2(kk,  j,2)*xc(kk,ic1)
! vec         end do            ! kvec
                               !if(i.ne.j) then
            end if
                            !do j=1,c_nnrro2
          end do

! STANDARD DIAGNOSTIC WRITE
         if(c_kkw.gt.0) then
          if(i.eq.1) write(c_out,901)
          write(c_out,903) i,nr, ic, c_tchem(ic), xc(c_kkw,ic)          &
     &     ,ratero2(c_kkw,i,1), ratero2(c_kkw,i,2), ratek(c_kkw,nr)
  901     format(/,'SETRO2: i nr ic   spec  XC  RATE CONSTANTS: ',      &
     &              'self cross  parameterized')
  903     format(3i5,a8,1pe10.3,2x,3(1pe10.3))
                  ! end write
         end if
!

! END  LOOP FOR PARAMETERIZED RO2 REACTIONS
                    !do  i=1,c_nnrro2
       end do

!  END SETRO2
 2000 return
      END
! -------------------------------------




       subroutine ohwrite(kw)

! This prints a summary of odd-h radical sources by category,
!  and also sensitivity to OH (d(lnHx)/d(lnOH)) by category.
!
! (Representing the components of oddhsum and oddhdel
!   used in the odd-h radical solution.)

!
! Inputs:    Species concentrations (xc), reaction rates (rr),
!              odd-h sums
!
! Outputs:   None
!
!
! Called by:    boxmain,  ohsolve
!
! Calls to:     None.
!
! ---------------------------------------------
! History:
!  12/06 Written by Sandy Sillman from boxchemv7.f
!
! -------------------------------------------------------------------

! -------------------------------------------------------

      implicit none

! LOCAL VARIABLES:

! hxsum(20,2):  Summed (1) net Hx source and
!                (2) Hx sensitivity to OH (as dHx/dOH*[OH])
!                for different source categories

                                    ! Summed Hx source and dH/dOH*[OH]
      double precision hxsum(20,2)

! -------------------------------------------------------

       kk=1

         if(kw.le.0) return

        write(c_out,1858) senhcat(kw,10), senhcat(kw,3)
 1858   format(/,' OH-SENSITIVITY COEFF:  HO2, RO2=',2f10.4)

! HX WRITE MATRIX FOR HX SOURCES.
        write(c_out,1859)
 1859   format(/,'ODD-H RADICAL SOURCES AND SINKS:')

! INITIAL ZERO
        do 1860 ii=1,20
         hxsum(ii,1) = 0.
         hxsum(ii,2) = 0.
 1860   continue

! PRIOR ODD HYDROGEN (16).  (COPY FROM PRIOR IN 'OHSOLVE').
      do 1865 ic=1,c_nchem2
        if((c_icat(ic).eq.3.or.c_icat(ic).eq.9.or.c_icat(ic).eq.10      &
     &        .or.c_icat(ic).eq.8).and.                                 &
     &          .not.c_lsts(ic))  then

         if(ic.eq.c_npequil(ic)) then
            hxsum(16,1) = hxsum(16,1) +   c_xcin(kk,ic) - xc(kk,ic)
            alpha(kk)=0.
            if(c_rl(kk,ic)+xc(kk,ic).gt.0) then
             alpha(kk) =  (c_rp(kk,ic)+c_rl(kk,ic))*xc(kk,ic)           &
     &           /(c_rp(kk,ic)+c_rl(kk,ic)+xc(kk,ic))
             hxsum(16,2) = hxsum(16,2) - senhcat(kk,c_icat(ic))         &
     &         * alpha(kk)
            end if
         else

           if(c_h2oliq(kk).gt.0) then
               hxsum(16,1) = hxsum(16,1) + (  c_xcin(kk,ic) - xc(kk,ic))&
     &            *c_h2oliq(kk)*avogadrl

               alpha(kk)=0.
               if(c_rl(kk,ic)+xc(kk,ic).gt.0) then
                 alpha(kk) = ( c_rp(kk,ic)+c_rl(kk,ic))                 &
     &                            *xc(kk,ic)*c_h2oliq(kk)*avogadrl      &
     &              /(c_rp(kk,ic)+c_rl(kk,ic)                           &
     &                       +xc(kk,ic)*c_h2oliq(kk)*avogadrl)
                  hxsum(16,1) = hxsum(16,1) - senhcat(kk,c_icat(ic))    &
     &              * alpha(kk)
               end if
           end if

         end if

       end if
 1865 continue

! LOOP THROUGH REACTIONS, SET SENHCAT FOR EACH.
! THEN SUM ODDHSUM ODDHDEL BY SPECIES CATEGORIES
        do 1870 nr=1,c_nreac
         icat1 = 0
         icat2 = 0
         icatp = 0
         icatp2 = 0
         if(c_reactant(nr,1).gt.0) then
             icat1=c_icat(c_reactant(nr,1))
         end if
         if(c_reactant(nr,2).gt.0) then
            icat2=c_icat(c_reactant(nr,2))
         end if
         if(c_product(nr,1).gt.0) then
            icatp=c_icat(c_product(nr,1))
         end if
         if(c_product(nr,2).gt.0) then
            icatp2=c_icat(c_product(nr,2))
         end if
         senshx( kw,1) = 0.
         if(icat1.gt.0) senshx( kw,1) = senshx( kw,1)                   &
     &     + senhcat( kw,icat1)
         if(icat2.gt.0) senshx( kw,1) = senshx( kw,1)                   &
     &     + senhcat( kw,icat2)

!           if(nr.ge.370.and.nr.le.372) write(c_out,*)  nr, icat1,
!    *        icat2,icatp,icatp2,c_oddhx(nr)

! SUM BY SPECIES CATEGORIES:
! (1) HO2+HO2->H2O2.
         if(icat1.eq.10.and.icat2.eq.10) then
           hxsum(1,1) = hxsum(1,1)+ c_rr( kw,nr)*c_oddhx(nr,1)
           hxsum(1,2) = hxsum(1,2)+ c_rr( kw,nr)*c_oddhx(nr,1)          &
     &   *senshx( kw,1)
         end if
! (2) HO2+RO2->ROOH
!      excluding CO3 (HCO3, icatp=20)
         if( (  (icat1.eq.10.and.icat2.eq.3)                            &
     &    .or.(icat2.eq.10.and.icat1.eq.3)  )                           &
     &    .and.(icatp.ne.20.and.icatp2.ne.20)                           &
     &                                      )then
           hxsum(2,1) = hxsum(2,1)+ c_rr( kw,nr)*c_oddhx(nr,1)
           hxsum(2,2) = hxsum(2,2)+ c_rr( kw,nr)*c_oddhx(nr,1)          &
     &   *senshx( kw,1)
         end if
! (3) RO2+RO2->products
         if ((icat1.eq. 3.and.icat2.eq.3).or.c_nrk(nr).eq.-13) then
           hxsum(3,1) = hxsum(3,1)+ c_rr( kw,nr)*c_oddhx(nr,1)
           hxsum(3,2) = hxsum(3,2)+ c_rr( kw,nr)*c_oddhx(nr,1)          &
     &   *senshx( kw,1)
! TEMPORARY TEST
!          write(c_out,12001) nr, (c_treac(ir,nr),ir=1,5),
!    *      c_rr( kw,nr),c_oddhx(nr,1), hxsum(3,1)
! 12001      format(i5,2x,a8,'+',a8,'=>',a8,'+',a8,'+',a8,/,3(1pe10.3))
         end if
! (4) H2O2, ROOH+hv
         if(icat1.eq.4.or.icat2.eq.4) then
           hxsum(4,1) = hxsum(4,1)+ c_rr( kw,nr)*c_oddhx(nr,1)
           hxsum(4,2) = hxsum(4,2)+ c_rr( kw,nr)*c_oddhx(nr,1)          &
     &   *senshx( kw,1)
         end if
! (5) OH+HO2
         if( (icat1.eq.9.and.icat2.eq.10)                               &
     &   .or.(icat2.eq.9.and.icat1.eq.10) ) then
           hxsum(5,1) = hxsum(5,1)+ c_rr( kw,nr)*c_oddhx(nr,1)
           hxsum(5,2) = hxsum(5,2)+ c_rr( kw,nr)*c_oddhx(nr,1)          &
     &   *senshx( kw,1)
         end if

! (6)  HNO3 production;  including aqueous NO3L+HO2-.
         if((      (icat1.eq.9.and.icat2.eq.12)                         &
     &       .or.  (icat2.eq.9.and.icat1.eq.12)                         &
     &       .or. (icat1.eq.14.and.icat2.eq.10)                         &
     &       .or. (icat1.eq.10.and.icat2.eq.14)                         &
     & ) .and. icatp.ne.6)  then
           hxsum(6,1) = hxsum(6,1)+ c_rr( kw,nr)*c_oddhx(nr,1)
           hxsum(6,2) = hxsum(6,2)+ c_rr( kw,nr)*c_oddhx(nr,1)          &
     &   *senshx( kw,1)
         end if

! (7,8)  HNOx:  SEPARATE INTO SINKS AND SOURCES
! JUST SO THAT 'EXCHANGE' CAN BE REMOVED.
         if (icat1.eq.6.or.icat2.eq.6              ) then
           hxsum(7,1) = hxsum(7,1)+ c_rr( kw,nr)*c_oddhx(nr,1)
           hxsum(7,2) = hxsum(7,2)+ c_rr( kw,nr)*c_oddhx(nr,1)          &
     &   *senshx( kw,1)
         end if

         if (                            icatp.eq.6) then
           hxsum(8,1) = hxsum(8,1)+ c_rr( kw,nr)*c_oddhx(nr,1)
           hxsum(8,2) = hxsum(8,2)+ c_rr( kw,nr)*c_oddhx(nr,1)          &
     &   *senshx( kw,1)
         end if

! (9,10) PANs SINKS, SOURCES.  (Note: ODDHDEL for PAN is re-set below.)
         if (icat1.eq.5.or.icat2.eq.5              ) then
           hxsum(9,1) = hxsum(9,1)+ c_rr( kw,nr)*c_oddhx(nr,1)
           hxsum(9,2) = hxsum(9,2)+ c_rr( kw,nr)*c_oddhx(nr,1)          &
     &   *senshx( kw,1)
         end if

         if (                            icatp.eq.5) then
           hxsum(10,1) = hxsum(10,1)+ c_rr( kw,nr)*c_oddhx(nr,1)
           hxsum(10,2) = hxsum(10,2)+ c_rr( kw,nr)*c_oddhx(nr,1)        &
     &   *senshx( kw,1)
         end if

! (11) RNO3
         if  (icatp.ne.5.and.                                           &
     &    (   (icat1.eq.3.and.icat2.eq.13)                              &
     &   .or. (icat2.eq.3.and.icat1.eq.13)  )    )then
           hxsum(11,1) = hxsum(11,1)+ c_rr( kw,nr)*c_oddhx(nr,1)
           hxsum(11,2) = hxsum(11,2)+ c_rr( kw,nr)*c_oddhx(nr,1)
         end if

! (12) O3+hv
         if  (icat1.eq.11.and.icat2.eq.0)   then
           hxsum(12,1) = hxsum(12,1)+ c_rr( kw,nr)*c_oddhx(nr,1)
           hxsum(12,2) = hxsum(12,2)+ c_rr( kw,nr)*c_oddhx(nr,1)        &
     &   *senshx( kw,1)
         end if
! (13)  ALD+hv
         if  (icat1.le. 2.and.icat2.eq.0                                &
     &                        .and.c_reactant(nr,2).eq.-1) then
           hxsum(13,1) = hxsum(13,1)+ c_rr( kw,nr)*c_oddhx(nr,1)
           hxsum(13,2) = hxsum(13,2)+ c_rr( kw,nr)*c_oddhx(nr,1)        &
     &   *senshx( kw,1)
         end if
! (14)  O3+OLEFIN
         if( (icat1.eq.11.and.(icat2.eq.1.or.icat2.eq.2))               &
     &   .or.(icat2.eq.11.and.(icat1.eq.1.or.icat1.eq.2))  )then
           hxsum(14,1) = hxsum(14,1)+ c_rr( kw,nr)*c_oddhx(nr,1)
           hxsum(14,2) = hxsum(14,2)+ c_rr( kw,nr)*c_oddhx(nr,1)        &
     &   *senshx( kw,1)
         end if

! (15)  AQUEOUS O2- + HCO3-.   (expand to include H+, OH- = cat 17,18?)
         if( (icat1.eq.20.or.icat2.eq.20.or.                            &
     &                           icatp.eq.20.or.icatp2.eq.20) .or.      &
     &       (icat1.eq.0.or.(icat2.eq.0.and.c_reactant(nr,2).gt.0.))    &
     &     .or.(icat1.eq.8.or.icat2.eq.8)                               &
     &       ) then
           hxsum(15,1) = hxsum(15,1)+ c_rr( kw,nr)*c_oddhx(nr,1)
           hxsum(15,2) = hxsum(15,2)+ c_rr( kw,nr)*c_oddhx(nr,1)        &
     &   *senshx( kw,1)
!           if(nr.ge.370.and.nr.le.372) write(c_out,*)  nr, icat1,
!    *        icat2,icatp,icatp2,c_oddhx(nr,1)
         end if
 1870  continue

! CORRECTION FOR 'EXCHANGE' REACTIONS:  PAN, HNOx EXCHANGE
!  IS REMOVED (APPROXIMATELY) FROM ODDHDEL
!   (NOTE:  THIS CAUSES ERROR WITH HONO)
       if((0.-hxsum(8,1)).gt.hxsum(7,1).and.hxsum(8,1).ne.0) then
         hxsum(8,2) = hxsum(8,2)*(1.+hxsum(7,1)/hxsum(8,1))
        else
         hxsum(8,2) = 0.
        end if

! APPROXIMATE RE-SET FOR PAN ODDHDEL.
       if((0.-hxsum(10,1)).gt.hxsum(9,1).and.hxsum(10,1).ne.0) then
         hxsum(10,2) = hxsum(10,2)*(1.+hxsum(10,1)/hxsum(10,1) )
        else
         hxsum(10,2) = 0.
        end if

! MISCELLANEOUS(17) AND TOTAL SUM (18) AND SUM WITHOUT RO2 (19)
!   (NOTE MISCELLANEOUS OFTEN CORRECTS FOR APPROXIMATION IN PAN ODDHDEL)
       hxsum(17,1) = oddhsum( kw,1)
       hxsum(17,2) = oddhdel( kw,1)
       hxsum(18,1) = oddhsum( kw,1)
       hxsum(18,2) = oddhdel( kw,1)
       hxsum(19,1) = oddhsum( kw,2)
       hxsum(19,2) = oddhdel( kw,2)
       do 1875 ii=1,16
        hxsum(17,1) = hxsum(17,1)-hxsum(ii,1)
        hxsum(17,2) = hxsum(17,2)-hxsum(ii,2)
 1875  continue

! WRITE ODD-H SOURCES AND SINKS.  NOTE DISCREPANCY IN PRIOR HX.
! THE TRUE ODDHSUM USES (XXO-XRP, prior) IN THE CALC FOR NEW OH.
! HXSUM RECORDS (XXO-XRP) for RO2 + (XXO-XR,new) for OH+HO2.
! THIS CAUSES A SMALL DISCREPANCY BETWEEN HXSUM AND ODDHSUM
! THE DISCREPANCY IS ADDED INTO HXSUM-MISCELLANEOUS.

      write(c_out,1876) ((hxsum(ii,i),i=1,2),ii=1,19)
 1876 format(/,' ---ODD-H SOURCES---     ODDHSUM   ODDHDEL',/,          &
     &         ' HO2+HO2->H2O2        ',2(1pe10.3),/,                   &
     &         ' HO2+RO2->ROOH        ',2(1pe10.3),/,                   &
     &         ' RO2+RO2-> prod       ',2(1pe10.3),/,                   &
     &         ' H2O2,ROOH+hv         ',2(1pe10.3),/,                   &
     &         ' OH+HO2 -> SINK       ',2(1pe10.3),/,                   &
     &         ' OH+NO2->HNO3         ',2(1pe10.3),/,                   &
     &         ' HONO, HNO4 SINK      ',2(1pe10.3),/,                   &
     &         ' HONO, HNO4 SOURCE    ',2(1pe10.3),/,                   &
     &         ' PANS SINK            ',2(1pe10.3),/,                   &
     &         ' PANS SOURCE          ',2(1pe10.3),/,                   &
     &         ' RO2+NO->RNO3         ',2(1pe10.3),/,                   &
     &         ' O3+hv->2OH           ',2(1pe10.3),/,                   &
     &         ' ALD+hv               ',2(1pe10.3),/,                   &
     &         ' O3+OLEFIN            ',2(1pe10.3),/,                   &
     &         ' AQUEOUS HCO3-        ',2(1pe10.3),/,                   &
     &         ' PRIOR OH, HO2,RO2    ',2(1pe10.3),/,                   &
     &         ' MISCELLANEOUS        ',2(1pe10.3),/,                   &
     &         ' FINAL SUM            ',2(1pe10.3),/,                   &
     &         ' FINAL SUM w/o RO2    ',2(1pe10.3)        )
!
!
! SPECIAL AQUEOUS DEBUG WRITE - TEMPORARY. aqueous reactions 370-376
!         do 1385 nr=384,386
!          write(c_out,102) nr,(c_treac(i,nr),i=1,5),
!    *      c_rr( kw,nr) , ratek( kw,nr)
! 1385      continue

  102  format(i4,2x,a8,'+',a8,'=>',a8,'+',a8,'+',a8,2x,3((1pe10.3),2x))

! END OHWRITE
 2000 return
      END
! ----------------------------------------------------
!
! --------------------------------------------------------------
!
! --------------------
! END  OF chemsolve/quadchem. (aquasolve may be attached below.)
! --------------------
!
! ==============================================================
!

      subroutine aquasolve

! THIS  CALCULATES (H+) AND AQUEOUS SPECIES CONCENTRATIONS
!   (MOLES PER LITER)  BASED ON PRIOR (H+).
!
! THE SOLUTION FOR (H+)  MUST BE RUN ITERATIVELY.
! EACH AQUASOLVE CALL REPRESENTS A SINGLE ITERATION.
!
! CHEMISTRY IS ASSUMED TO BE REPRESENTED BY DISSOCIATING SPECIES
! WITH CHAINS OF UP TO THREE DISSOCIATIONS
! (GAS->AQUEOUS, AQUEOUS->SINGLE ION, ION->DOUBLE ION)
! EACH RELEASING H+ AND OH-.

! THIS RESULTS IN A SINGLE FOURTH-ORDER EQUATION FOR H+
!  (0 = THE SUM OF H+, OH-, CATIONS AND ANIONS, ALL FUNCTIONS OF H+)
! WHICH IS SOLVED ITERATIVELY USING NEWTON-RAFSON.
! TYPICALLY IT IS CALLED FROM WITHIN THE GAS-PHASE ITERATION.
!
! INCLUDES LELIEVELD 1991,etc. FOR WATER DROPLET DIFFUSION
! (SEE 'NEWTON-RAFSON' AND 'Lelieveld' FOR DETAILS BELOW.)
!
! INCLUDES GAS-PHASE DIFFUSION MODIFICATION FOR PARTITIONING
!  WHERE GAS->AQ TRANSFER IS SLOWER THAN AQUEOUS LOSS.
!  (with ACCOMODATION coefficients - see ACCOMODATION)
!
! NEW ADD:  GAS/AQUEOUS PARTITIONING BASED ON GAS/AQUEOUS SPEED.
!
! NOTE:  DROPLET RADIUS, GAS DIFFUSION CONSTANT, HARD-WIRED. PI also.
!
! ----------------
! A NOTE ON UNITS:  WITHIN THIS LOOP, THE GAS-MASTER SPECIES
! IS CONVERTED INTO LIQUID UNITS (MOLES GAS PER LIQUID WATER).
!   (=MOLECULES/CM3 /(AVOGADRL*AQUA(KK)).
! THE HENRY'S LAW COEFFICIENTS (RATEH) WERE ALSO CONVERTED
!   (MULTIPLIED BY AVOGADRL*AQUA(KK).)
! THIS ALLOWS FOR EASY CONSERVATION OF THE GAS+AQUEOUS SPECIES SUM.
! GAS-MASTER SPECIES IS CONVERTED BACK TO MOLECULES/CM3 AT THE END.
!
! NOTE:  0.1-1e6 gram/cm3 is typical.
! ----------------
!
! Inputs:    Species concentrations (xc), chemistry, LWC
!
! Outputs:   Gas and aqueous concentrations (xc),
!               in mole/cm3 (gas) and mole/liter (aq)
!
!
! Called by:    quadchem
!
! Calls to:     None.
!
! ---------------------------------------------
! History:
!  12/06 Written by Sandy Sillman from boxchemv7.f
!
! -------------------------------------------------------------------

! ---------------------------------------------------------------
      implicit none

      character*8 tsum
      double precision sum

                                         ! 1/[H+]
      double precision xhinv(c_kvec)
                                         ! 1/[OH]
      double precision xohinv(c_kvec)
                                         ! 1/Kw =1/[H+][OH-}
      double precision  xkwinv(c_kvec)

                                         ! Test for LWC>0 in loop
      double precision xtest
                                         ! Variable for write statement
      double precision xxx1
                                         ! Variable for write statement
      double precision xxx2
                                      ! Aq conversion fac for write
      double precision acquacon

      kk=1

! IF ACQUA=0, RETURN.  ONLY FOR NONVECTORIZED VERSION.
      xtest=0.
!     do 16001 kk=1,c_kmax
       if(c_h2oliq(kk).gt.xtest) xtest=c_h2oliq(kk)
16001 continue
!     if(xtest.eq.0.) return
      if(xtest.le.1.000E-25) return

! AVOGADRL converts MOLES/LITER to MOLECULES/CM3.-> entered in chemvars
! RTCON
!     avogadrl = 6.02E+20

! pi (if not built-in special)-> entered in chemvars

! H+ species number  -ih, ioh replaced with c_nhplus, c_nohmin
!      c_nhplus=c_aqueous(1,2)
!      c_nohmin = c_aqueous(1,3)

! DROPLET RADIUS (.001 cm) AND DIFFUSION COEFFICENT (2E-5 cm2/sec)
! AND GAS-PHASE DIFFUSION COEFFICIENT (0.1 cm2/sec)
!   (all with values from Lelieveld and Crutzen, 1991)
! AND "RU" PARAMETER FOR  molecular speed (Barth, personal comm)
!   (8.314e7 g-cm2/s2-mol-K)   (note: 8.314e0 kg-m2/s2-mol-K)

! v      do kk=1,c_kmax
!      c_DROPLET(kk) = .001   => now INPUT VALUE
!        end do              ! do kk=1,c_kmax

!      DROPDIF = 2.0E-05  - entered as parameter in chemvar1
!      DIFGAS  = 0.1  - entered as parameter in chemvar1
!       RUMOLEC = 8.314E7 - entered as parameter in chemvar1

!  (   VMOLEC = MOLECULAR SPEED, CALCULATED BELOW)


! NEW PRELIMINARY:  CALCULATE ADJUSTMENT TO HENRY'S LAW COEFFICIENTS
!  TO REPRESENT DROPLET DIFFUSION LIMITATION
!  (Lelieveld, J. At. Chem 12, 229, 1991 - see p. 241).
!
!  Q = Cavg/Csurf = 3 (coth q /q - 1/q**2)**-1;  q=r*(ka/Da)**0.5
!
!   where r= droplet radius (.001cm)  Da=droplet diffusion (2e-5 cm)
!   ka = pseudo-1st-order aqueous loss rate.
!  This Q applies only to the species component that originated in the
!   gas phase and was transported to aqueous (Sg) as opposed to being
!   produced chemically in the aqueous phase (Pa).
!
!  Total Q' = (Pa + QSg)/(Pa+Sg);  Sg=source to aqueous from gas.
!
!  (Pa, Sg should be from prior iteration.  Here,
!   Sg = (rpgas+c_xcin) * prior aq/gas ratio (= rlaq/(rlaq+rlgas).  Slig
!   other options:  (i)= (Pgas+c_xcin)*(xraq/xrtot).  (ii)=rlaq-rpaq  )
!

! ------------
! BEGIN LOOP FOR DIFFUSION-HENRY'S LAW MODIFICATION.
! ------------
        do  nrh=1,c_nreach
         ic = c_henry(nrh,1)
         ich=c_ncequil(ic,1)

! DIFFUSION-MODIFIED HENRY'S LAW COEFFICIENT: FIRST SET EQUAL TO ONE
! ALSO, SAVE PRIOR RHDIF
!        do kk=1,c_kmax
           prior(kk) = rhdif(kk,nrh)
           rhdif(kk,nrh) = 1.
!        end do

! FOR ITER>1, USE PRIOR RP, RL TO SET DIFFUSION-MODIFICATION.

         if(c_iter.gt.1.and.c_nequil(ic).gt.0)  then

! PRELIMINARY ZERO
           do i=1,3
!            do kk=1,c_kmax
              rpro(kk,i) = 0.
              rloss(kk,i) = 0.
              xrp(kk,i) = 0.
!             rpro(kk,i) = 0.00001
!             rloss(kk,i) = 0.00001
!             xrp(kk,i) = 0.1
!            end do
           end do

! SUM AQUEOUS CONCENTRATIONS IN GAS-EQUIVALENT UNITS (xrp1)
! ALSO SUM AQUEOUS PRODUCTION (rpro1) AND LOSS (rloss1)
           do    neq=1,c_nequil(ic)
            icq = c_ncequil(ic,neq)
            if(icq.gt.0) then

! v           do  kk=1,c_kmax
              if(c_h2oliq(kk).gt.0) then
                if(c_iter.le.2) then
                 xrp(kk,1) =xrp(kk,1) + xc(kk,icq)*c_h2oliq(kk)*avogadrl
                else
! xclastq = from prior iteration (=xc end of last aquasolve)
!
! OPTION and possible ERROR:
!    (1)  Why use xclastq and not current xr?
!    (2)  Were rp preserved from prior iteration?
!
                 xrp(kk,1) =xrp(kk,1)                                   &
     &             + xc     (kk,icq)*c_h2oliq(kk)*avogadrl
!    *             + xclastq(kk,icq)*c_h2oliq(kk)*avogadrl
                end if
                rpro(kk,1) = rpro(kk,1) + c_rp(kk,icq)
                rloss(kk,1) = rloss(kk,1) + c_rl(kk,icq)
                if(neq.eq.1)  xrp(kk,2) =  xrp(kk,1)
              end if
! v           end do

             end if
           end do

! PSEUDO-FIRST-ORDER AQUEOUS LOSS CONSTANT (alpha)
!  (NOTE:  if RL and XR=0, initial values above make lifetime long.)

!          do kk=1,c_kmax
           if(c_h2oliq(kk).gt.0) then
             alpha(kk) = 0.00001
             if(xrp(kk,1).gt.0.and.rloss(kk,1).gt.0)                    &
     &        alpha(kk) = rloss(kk,1)/(xrp(kk,1)*c_time)
           end if
!          end do

! Lelieveld Q-FACTOR FOR AQUEOUS DIFFUSION  (beta)
!
! v        do kk=1,c_kmax
           if(c_h2oliq(kk).gt.0) then
             gamma(kk) = c_DROPLET(kk) * sqrt(alpha(kk)/DROPDIF)

! PROTECT AGAINST EXTREME q (=droplet ratio)
             if(gamma(kk).lt..01) then
              beta(kk)=1.
             else
              if(gamma(kk).gt.100.) then
               beta(kk)=0.001
              else

               beta(kk) = (exp(gamma(kk)) + exp(0.-gamma(kk)) )         &
     &                  / (exp(gamma(kk)) - exp(0.-gamma(kk)) )
                if(c_kkw.gt.0) then
                  xxx1 = beta(c_kkw)
                end if
               beta(kk) = 3.* (beta(kk)/gamma(kk) - 1./(gamma(kk)**2) )
                if(c_kkw.gt.0) then
                 xxx2 = beta(c_kkw)
                end if
               if(beta(kk).gt.1.) beta(kk)=1.
               if(beta(kk).lt.0.) beta(kk)=0.
              end if
             end if

           end if
! v        end do

! TEST WRITE
! c          if(c_kkw.gt.0) write(c_out,19104) xxx1, xxx2
! c 19104      format(' TEST Q (0-1). coth q, formula Q=',2e10.3)
!          if(c_kkw.gt.0) write(c_out, 19101)
!    *      nrh, beta(c_kkw), gamma(c_kkw), alpha(c_kkw)
! 19101      format(/,' TEST AQUEOUS DIFF: NRHENRY, Q, q, La(sec-1)='
!    *        ,i5,3e10.3)

! Lelieveld Q-FACTOR, ADJUSTED FOR AQUEOUS PRODUCTION VS DIFFUSION FROM
! Q APPLIED TO GAS DIFFUSION ONLY:  Q' = (Sgas*Q + Saq)/(Sgas+Saq)
!
! (Final option for S=source of aqueous from gas:
!  S = (rpgas+c_xcin) * aq/gas ratio (= rlaq/(rlaq+rlgas).  Slight overe
!
!  alternatives: (i)  aq/gas=1; aq/gas=Ca/Ct where H=Ca/Cg
!               (ii) S = aqueous rl-rp if >0.
! )

! v          do kk=1,c_kmax
             if(c_h2oliq(kk).gt.0) then

              gamma(kk) = (  c_xcin(kk,ic) + c_rp(kk,ic))
              if(rloss(kk,1).gt.0)                                      &
     &         gamma(kk) = (  c_xcin(kk,ic) + c_rp(kk,ic))              &
     &                  *rloss(kk,1)/(rloss(kk,1)+c_rl(kk,ic))

! Options
!             gamma(kk) = (  c_xcin(kk,ic) + c_rp(kk,ic))

!             gamma(kk) = (  c_xcin(kk,ic) + c_rp(kk,ic)) *rateh(kk,nrh)
!    *                             /(rateh(kk,nrh)+1.)

!             gamma(kk) = rloss(kk,1) - rpro(kk,1)
!             if(gamma(kk).lt.0) gamma(kk).eq.0.)


! Q adjustment:  Q'=rhdif;  Q=beta; Sgas=gamma; Saq=rpro
!  Apply only if aqueous concentration is not zero.

              if(xrp(kk,1).gt.0.and.(gamma(kk)+rpro(kk,1).gt.0))        &
     &        rhdif(kk,nrh)  = (beta(kk)*gamma(kk) + rpro(kk,1))        &
     &                       / (gamma(kk) +          rpro(kk,1))

             end if
! v          end do

!  TEST WRITE
!              if(c_kkw.gt.0) write(c_out, 19107) rateh(c_kkw,nrh),
!    *         rpro(c_kkw,1),   c_xcin(c_kkw,ic), c_rp(c_kkw,ic)
! 19107        format(' TEST rateh rproq c_xcin rpgas=',4e10.3)
!            if(c_kkw.gt.0) write(c_out,19108) c_rl(c_kkw,ic)
!    *         ,rloss(c_kkw,1) ,alpha(c_kkw)
! 19108        format(' TEST rlgas rlaq, Laq(s-1)=',3e10.3)
!            if(c_kkw.gt.0) write(c_out,19103) gamma(c_kkw)
!    *         , rhdif(c_kkw,nrh)
! 19103        format(' TEST S (=RPGAS*(aq/gas)); MODIFIED Q (0-1): '
!    *             ,2e10.3)


         end if
! END IF FOR ITER>1, AQUEOUS>0.

! ENTER COMBINED HENRY-S LAW-w AQ DIFFUSION (relative units).

!        do kk=1,c_kmax
         if(c_h2oliq(kk).gt.0) then
          rhdif(kk,nrh) = rhdif(kk,nrh)*rateh(kk,nrh)
         end if
!        end do
!

! DIAGNOSTIC WRITE
           if(c_kkw.gt.0) then
             write(c_out,19105) (c_treach(i,nrh),i=1,2)                 &
     &        ,rateh(c_kkw,nrh), rhdif(c_kkw,nrh)
19105         format(a8,'=',a8,'  HENRYs LAW COEFF.=',1pe10.3,          &
     &       '  H+DROPLET DIFF COEF=', 1pe10.3)
           end if

! -----------------------------------------------------------
! GAS-PHASE DIFFUSION MODIFICATION:
! ADJUST GAS/AQUEOUS RATIO TO ACCOUNT FOR CASE WHERE AQUEOUS LOSS RATE
!  (FROM AQUEOUS AND IONIC EQUILIBRIA SPECIES)
!  IS FASTER THEN THE NEEDED GAS-AQUEOUS TRANSFER.
! -----------------------------------------------------------
!
!
! USES ACCOMODATION COEFFICIENTS, FORMULAS IN Lelieveld AND INFO
!  FROM MARY BARTH.

! PARTITION COEFFICIENT IS BASED ON STEADY STATE BETWEEN Pg, Pa,
! Lg, La, Eg, Ea=Eg/H.  Eg calculated from Lelieveld, Barth.
! Lg, La, Eg in s-1;  Pg, Pa in equivalent units.
!
! (note rpro(kk,1) = aqueous production; rloss(kk,1)=aqloss,
!  c_rp(kk,ic) = gas pro, c_rl(kk,ic) = aqueous pro; xc(kk,ic) = gas cnc
!  xrp(kk,2) = aqueous concentr (w/o ion sum), gas units.
!
!  (Pg-(Lg+Eg)Cg+Ea"Ca' = 0.;  Pa'+EgCg-(Ea'+La')Ca' = 0.
!    where Ca', Pa', La',Ea' are for sum of aq-equil species;
!    See hand notes in Lelieveld 1991)
!
! AQUEOUS/GAS = (H*(Pa+Pg) + H(Lg/Eg)*Pa)/(Pa+Pg+H(La/Eg)*Pg)
! HENRY ADJUSTMENT = (Pa + Pg + (Lg/Eg)Pa)/(Pa+Pg+H(La/Eg)Pg)

! *** ONLY IF c_iter>1. AND WITH SOFTENING.
! ----------------------------------------------------

! ESTABLISH GAS=>AQUEOUS EXCHANGE RATE (Eg).
!  MOLEC SPEED (VMOLEC, gamma) = sqrt(8*ru*temp/(pi*c_molwt))
!    = 3e4 cm/s, speed of sound.  (Barth).
!
!   Eg (s-1) = [(DROPLET**2/3DIFGAS) + 4DROPLET/(3*VMOLEC*ACCOM)]**-1
!   (Lelieveld).
!   THEN MULTIPLY BY LIQUID WATER CONTENT (acqua)
!
! (STILL WITHIN HENRY'S LAW LOOP)
! ----------------------------------------------------
!
! OPTION:  INCLUDE OR OMIT, WITH ITER CONTROL HERE.

         if(c_iter.gt.1) then
!        if(c_iter.lt.0) then

! v       do kk=1,c_kmax
           gamma(kk) = sqrt( 8.*RUMOLEC*c_temp(kk)/(pii*c_molwt(nrh)) )
           egasaq(kk,nrh) = c_h2oliq(kk)/                               &
     &             ( (c_DROPLET(kk)**2/(3.*DIFGAS))                     &
     &             + (4.*c_DROPLET(kk)/(3.*gamma(kk)*c_accom(nrh)))  )


           beta(kk) = rpro(kk,1) + c_rp(kk,ic)

! TEST WRITE
           if(c_kkw.gt.0)                                               &
     &       write(c_out,18099) gamma(kk), egasaq(kk,nrh), beta(kk)
18099      format(8(1pe10.3))

! GOT HERE
! 2009 CORRECTION
! THESE NEXT LINES WERE COMMENTED OUT IN quadchv7.f
!   WHICH GENERATES A SUCCESSFUL SOLUTION
!   (w/ these lines commented in GAS DIFF ADJUST alpha = 1.000)

!          if(beta(kk).lt.0.) beta(kk) = 0.
!          gamma(kk) = beta(kk)
!          if( c_rl(kk,ic).gt.0.and.(xc(kk,ic)-xrp(kk,1)).gt.0
!    *         .and.rpro(kk,1).gt.0.and.egasaq(kk,nrh).gt.0)
!    *     beta(kk) = beta(kk) + (
!    *                 ( c_rl(kk,ic)/(xc(kk,ic)-xrp(kk,1)) )
!    *                 /(c_time*egasaq(kk,nrh) ))     *rpro(kk,1)

! TEST WRITE
!          if(c_kkw.gt.0)
!    *       write(c_out,18099) c_rl(kk,ic), xc(kk,ic), xrp(kk,1),
!    *      rpro(kk,1), beta(kk)

! OLD  CRASH HERE
           if( rloss(kk,1).gt.0.and.(xrp(kk,2)).gt.0                    &
     &         .and.c_rp(kk,ic).gt.0.and.egasaq(kk,nrh).gt.0            &
     &         .and.rhdif(kk,nrh).ne.0)                                 &
     &     gamma(kk) = gamma(kk) + (                                    &
     &                ( (rloss(kk,1)/(xrp(kk,2)))                       &
     &                 /(c_time*egasaq(kk,nrh) )*rhdif(kk,nrh)) )       &
     &                  *c_rp(kk,ic)

! TEST WRITE
!          if(c_kkw.gt.0)
!    *       write(c_out,18099) rloss(kk,1), xrp(kk,2), c_rp(kk,ic),
!    *       gamma(kk)

           alpha(kk) = 1.
           if(beta(kk).gt.0.and.gamma(kk).gt.0)                         &
     &       alpha(kk) = beta(kk)/gamma(kk)

           rhdif(kk,nrh) = rhdif(kk,nrh)*alpha(kk)

! v       end do

! TEST WRITE
!           if(c_kkw.gt.0) write(c_out,19097)
!    *      egasaq(c_kkw,nrh),c_rl(c_kkw,ic), rloss(c_kkw,1)
!    *      ,xc(c_kkw,ic), xrp(c_kkw,2), xrp(c_kkw,1)
!    *      ,c_rp(c_kkw,ic), rpro(c_kkw,1)
! 19097     format('TEST: EGAS  RLgas  RLaq  XRgas XRaq XRaqall  RPgas'
!    *      , '  RPaq',/,8(1pe10.3))

! DIAGNOSTIC WRITE
           if(c_kkw.gt.0) then
             write(c_out,19095) (c_treach(i,nrh),i=1,2)                 &
     &        ,alpha(c_kkw), rhdif(c_kkw,nrh)
19095         format(a8,'=',a8,'  GAS DIFF. ADJUST.=',1pe10.3,          &
     &       '  HENRY+ DIFFUS COEFS=', 1pe10.3)
           end if

         end if
! END GAS-PHASE DIFFUSION MODIFICATION:
!
! MODIFY GAS/AQ RATIO FOR TROUBLESOME CONVERGENCE
         if(c_iter.gt.2) then
! v       do kk=1,c_kmax
           rhdif(kk,nrh) = (rhdif(kk,nrh)**0.5)*(prior(kk)**0.5)
! v       end do
         end if

! DIAGNOSTIC WRITE
           if(c_kkw.gt.0) then
              write(c_out,19096) (c_treach(i,nrh),i=1,2)                &
     &        ,rateh(c_kkw,nrh), rhdif(c_kkw,nrh)
19096         format(a8,'=',a8,'  HENRYs LAW COEFF.=',1pe10.3,          &
     &       '  H+GAS+DROP DIF COEF=', 1pe10.3)
           end if

! -----------------------------------------------------------
        end do
! -----------------------------------------------------------
! END LOOP FOR GAS-MASTER SPECIES FOR AQUEOUS DIFFUSION MODIFICATION
! -----------------------------------------------------------

! PRELIMINARY:  ZERO XR PRIOR (USED IN AQUEOUS SUMS). INITIALIZE H+,OH-.
! SUM PRIOR GAS AND AQUEOUS SPECIES INTO THE GAS-MASTER
! ALSO SUM PRODUCTION (RP in gas units)
!        RPRO1 =  SUMMED NET RP FOR THE INDIV. SPECIES
!        RPRO2 =  RUNNING SUM OF NET RP FOR IONS.
!        RPRO3 =  RUNNING SUM OF PRIOR ION CONCENTRATION
!         RPRO2/3, EFFECT OF PRIOR CHEM PRODUCTION OF IONS
!         WILL BE FACTORED INTO BETA (d/dH slope).

!     do 16002 kk=1,c_kmax
      if(c_h2oliq(kk).gt.0) then
       rpro(kk,1) = 0.
       rpro(kk,2) = 0.
       rpro(kk,3) = 0.
       if(xc(kk,c_nhplus).le.0) then
         xc(kk,c_nhplus) = 1.0E-05
         xc(kk,c_nohmin) = rateq(kk,1)/xc(kk,c_nhplus)
       end if
       if(xc(kk,c_nohmin).le.0) then
         xc(kk,c_nohmin) = rateq(kk,1)/xc(kk,c_nhplus)
       end if
      end if
16002 continue

      do 50 nrh=1,c_nreach
       ic = c_henry(nrh,1)

       if(c_nequil(ic).gt.0)  then

!        do 16003 kk=1,c_kmax
         if(c_h2oliq(kk).gt.0) then
          rpro(kk,1) = c_rp(kk,ic)-c_rl(kk,ic)
         end if
16003    continue

! SUM AQUEOUS SPECIES INTO THE GAS-MASTER, SUM GAS+AQUEOUS RPRO1.
         do 60 neq=1,c_nequil(ic)
          icq = c_ncequil(ic,neq)
          if(icq.gt.0) then

!    TEST WRITE - TEMPORARY
!               if(c_kkw.gt.0) write(c_out, 19004) c_tchem(ic)
!    *                , xc(c_kkw,ic)
! 19004           format(' AQUEOUS CALCULATION:   ', a8,2x,1pe10.3)

!           do 16004 kk=1,c_kmax
            if(c_h2oliq(kk).gt.0) then
             xc(kk,ic) = xc(kk,ic) + xc(kk,icq)*c_h2oliq(kk)*avogadrl
             rpro(kk,1) = rpro(kk,1) + c_rp(kk,icq)-c_rl(kk,icq)

!            if(c_kkw.gt.0) write(c_out, 19004) c_tchem(ic),xc(c_kkw,ic)

            end if
16004       continue
          end if
   60    continue

! SUM PRIOR NET CHEM ION PRODUCTION (RPRO2) AND ION SUM (RPRO3)
! ION CHEM. INFERRED FROM PRIOR GAS-AQ-ION PARTITIONING AND RPRO1.
! ALSO ZERO AQUEOUS CONCENTRATIONS

         do 65 neq=1,c_nequil(ic)
          icq = c_ncequil(ic,neq)
          if(icq.gt.0) then

            if(c_iter.gt.1) then
!            do kk=1,c_kmax     ! kk vector loop
              if(c_h2oliq(kk).gt.0) then
               if(xc(kk,ic).gt.0) then
                 rpro(kk,3) = rpro(kk,3) + (rpro(kk,1)/xc(kk,ic))       &
     &            * abs(c_ion(icq))*c_h2oliq(kk)*avogadrl*xc(kk,icq)
                                     !if(xc(kk,ic).gt.0) then
               end if
               rpro(kk,2) = rpro(kk,2) +                                &
     &            abs(c_ion(icq)) * c_h2oliq(kk)*avogadrl*xc(kk,icq)
                                 !if(c_h2oliq(kk).gt.0) then
              end if
!            end do           !kk vector loop
                           !if(c_iter.gt.1) then
            end if

! INTERIM DIAGNOSTIC WRITE
!         if(c_kkw.gt.0) then
!           write(c_out,19104) c_tchem(ic),c_tchem(icq),xc(c_kkw,ic),
!    *        xc(c_kkw,icq)
! 19104       format(/'TEST AQ. ADJUSTMENT FOR PRIOR ION PRODUCTION:',
!    *      /,' TCHEM ION XR XRQ=   ',a8,2x,a8,2x,2(1pe10.3))
!           write(c_out,19105) rpro(c_kkw,1),rpro(c_kkw,2),rpro(c_kkw,3)
! 19105       format(/,' GAS-EQUIV RP FOR GAS+AQ    =',1pe10.3,/,
!    *               ' GAS-EQUIVALENT ION SUM     =',1pe10.3,/,
!    *               ' GAS-EQUIVALENT ION RP SUM  =',1pe10.3)
!         end if

! ZERO AQUEOUS CONCENTRATIONS
!           do 16006 kk=1,c_kmax
             xc(kk,icq)=0.
16006       continue
          end if
   65    continue

       end if
   50 continue

! WRITE FOR RPRO AQUEOUS SUM -  DIAGNOSTIC WRITE
          if(c_kkw.gt.0) then
            write(c_out,19106)  rpro(c_kkw,2),rpro(c_kkw,3)
19106       format(/,' AQUEOUS ION PRODUCTION SUMMARY:'   ,/,           &
     &               ' GAS-EQUIVALENT ION SUM     =',1pe10.3,/,         &
     &               ' GAS-EQUIVALENT ION RP SUM  =',1pe10.3)
          end if

! --------------------------------------------------
! CALCULATE AQUEOUS CONCENTRATIONS BASED ON PRIOR H+.
! ALSO CALCULATE ACIDSUM, NET SUM OF AQUEOUS IONS (=ALPHA)
!  AND ACIDDEL, d(ACIDSUM)/dH+  (=BETA).
! THESE ARE THE NEWTON-RAFSON PARAMETERS.

! -------------------------------------------------------------
! FOR A GAS+AQUEOUS GROUP Xg, Xa, X1, X2 w/ constants Kh,K1, K2
! where Xa = Kh*Xg  X1*H = Xa*K1  X2*H=X1*K2  and Kw=H*OH:
!
! UNITS:  Kh was converted from (MOLES/LITER)/ATMOSPHERE
! to (MOLES/LITER)/(MOLEC/CM3) to (RELATIVE UNITS) in BRATES.
! K1, K2 are in MOLES/LITER.  Xg is converted to MOLES/LITER here.
! The MOLES/LITER conversion is based on LIQUID WATER (acqua).
!
! DOUBLE CATION:    (Xt=Xg+Xa+X1+X2)
!  Xg = Xt/ (1 + Kh*(1 + K1/H*(1 + K2/H) ) )
!  Xa = Xg*Kh   X1=Xa*K1/H  X2=X1*K2/H
!           ( X1 = Xt*Rh*R1*H / (H**2*(1+Kh) + H*Kh*K1 + Kh*K1*K2)   )
!  dX1/dH= X1/H - (X1**2/(Xt*Kh*K1*H) (2H(1+Kh)+Kh*K1)
!           ( X2 = XtKhK1K2/(H**2(1+Kh)+ H*Kh*K1 + Kh*K1*K2)         )
!  dX2/dH = (X2**2/(Xt*Kh*K1*K2)(2H(1+Kh)+Kh*K1)
! SINGLE CATION:    (K2=0)
!  dX1/dt = -(X1**2/(Xt*Kh*K1*H))*(1+Kh)
!
! DOUBLE ANION:
! Xg = Xt/ (1 + Kh*(1 + R1/OH*(1 + R2/OH) ) )
! Xa = Xg*Kh    X1=Xa*K1/OH   X2=X1*K2/OH
!           ( X1=XtKhK1OH/( OH**2(1+Kh) + OHKhK1 + KhK1K2 )
!           ( dX1/dH = -(OH/H)*dX1/dOH                                )
! dX1/dt= -X1/H + (X1**2/Xt*Kh*K1*H)*(2OH*(1+Kh)+Kh*K1) )
!           ( X2=XtKhK1K2/(OH**2(1+Kh)+OH*K1*Kh + K2*K1*Kh )
! dX2/dH =  (OH/H) * (X2**2/Xt*Kh*K1*K2)*(2OH(1+Kh)*Kh*K1)

! SINGLE ANION:
! dX1/dH =  (OH/H)* (X1**2)/(Xt*Kh*K1)*(1+Kh)
!        (   dX1/dH = (X1*Xg/Xt*H)*(1+Kh)                             )
!
! -------------------------------------------------------------
!
! SET INITIAL ALPHA (=ion sum) AND BETA (=d/dH)
! TO INCLUDE THE IMPACT OF (H+) and (OH-).  (Note:  H+>0, above.)
!
! SPECIAL FUNCTIONS:  1/H=xhinv(kk)   1/OH = xohinv(kk)
!                     1/Kw = xkwinv(kk)  1/Xt = gamma(kk)
!
!     do 16014 kk=1,c_kmax
      if(c_h2oliq(kk).gt.0) then
           xkwinv(kk) = 1./rateq(kk,1)
           xhinv(kk) = xkwinv(kk)*xc(kk,c_nohmin)
           xohinv(kk) = xkwinv(kk)*xc(kk,c_nhplus)
           alpha(kk) = xc(kk,c_nohmin)  - xc(kk,c_nhplus)
           beta(kk) =  1.+ xc(kk,c_nohmin)*xhinv(kk)
      end if
16014 continue
!
! DIAGNOSTIC TEST WRITE FOR H+ SOLVER
          if(c_kkw.gt.0) then
           write(c_out,1201) c_tchem(c_nhplus), alpha(c_kkw)            &
     &              , beta (c_kkw)
 1201      format(' AQ SPECIES, IONSUM, ION d/dH=',2x,a8,2(1pe12.3))
          end if

!         TEST WRITE
!         write(c_out,*) c_aqueous(1,2), c_aqueous(1,3)
!           write(c_out,*) rateq(1,1),xc(1,c_nhplus)
!         write(c_out,*) alpha(1), beta(1), xc(1,c_nhplus)

! BEGIN XR CALCULATION.
! LOOP THROUGH HENRY'S LAW TO IDENTIFY GAS-MASTER
! AND SOLVE FOR THE ASSOCIATED AQUEOUS GROUP.
      do 100 nrh=1,c_nreach
       ic = c_henry(nrh,1)
       ich=c_henry(nrh,2)
!               write(c_out,*) nrh,ic,ich
       if(c_nequil(ic).le.0) go to 100

! ZERO COUNTER FOR ION CHARGE
! AND INDICES FOR FIRST, SECOND ACID  OR BASE REACTIONS
      ionsum=0
      ica1 = 0
      ica2 = 0
      icb1 = 0
      icb2 = 0
      nra1 = 0
      nra2 = 0
      nrb1 = 0
      nrb2 = 0

!  CONVERT GAS-MASTER SUM TO LIQUID-EQUIVALENT UNITS (MOLES/LITER)
!  WITH ZERO-PROTECT
!        do 16017 kk=1,c_kmax
          if(c_h2oliq(kk).gt.0) then

!   TEST WRITE - TEMPORARY
!            if(c_kkw.gt.0) write(c_out, 19004) c_tchem(ic),xc(c_kkw,ic)

             xc(kk,ic)=xc(kk,ic)/(c_h2oliq(kk)*avogadrl)

!  TEST WRITE - TEMPORARY
!            if(c_kkw.gt.0) write(c_out, 19004) c_tchem(ic),xc(c_kkw,ic)

          end if
16017    continue


! HENRY'S LAW CALCULATION FOR SPECIES WITH NO AQUEOUS EQUILIBRIA
!  (dimensionless H=Ca/Cg, Cg=Ct/(1+H), Ca=Ct*H/(1+H) )

       if(c_nequil(ic).eq.1)  then
!        do 16021 kk=1,c_kmax
         if(c_h2oliq(kk).gt.0) then
         gamma(kk) = 1.                                                 &
     &        /(rhdif(kk,nrh) + 1.)
         xc(kk, ich) = (xc(kk,ic)*rhdif(kk,nrh)) * gamma(kk)
         xc(kk, ic)  = xc(kk,ic) *                                      &
     &        (gamma(kk)*(c_h2oliq(kk)*avogadrl) )
         end if
16021    continue

! LOOP FOR AQUEOUS EQUILIBRIA.  (c_nequil(ic).gt.1)
       else

! PRELIMINARY: IDENTIFICATION OF FIRST AND SECOND ACID-FORMING
! OR BASE-FORMING REACTIONS FOR THE AQUEOUS GROUP (ICA,NRA,ICB,NRB).
! THIS ESTABLISHES SOLUTION PROCEDURE FOR THE GROUP, TO BE USED BELOW.

         do 90 neq=2,c_nequil(ic)
          icq = c_ncequil(ic,neq)
          nrq = c_nrequil(ic,neq)
!               write(c_out,*) neq,nrq,icq,ic
          if(icq.gt.0.and.nrq.gt.0) then
            if(c_aqueous(nrq,3).eq. c_nhplus) then
              if(ica1.eq.0) then
                ica1=icq
                nra1=nrq
              else
                ica2=icq
                nra2=nrq
              end if
            end if
            if(c_aqueous(nrq,3).eq. c_aqueous(1,3)) then
              if(icb1.eq.0) then
                icb1=icq
                nrb1=nrq
              else
                icb2=icq
                nrb2=nrq
              end if
            end if
          end if
   90    continue

! AQUEOUS IC, NR RECORDED FOR FIRST AQUEOUS REACTION
!  (USED IF IT IS NOT ACID OR BASE REACTION).
        icq = c_ncequil(ic,2)
        nrq = c_nrequil(ic,2)

        if(icq.le.0.and.nrq.le.0)                                       &
     &     write(c_out,91) ic, c_tchem(ic), icq,nrq
   91   format(/,' CHEMISTRY INDEX ERROR IN AQUASOLVE:',/,              &
     &   ' IC, TCHEM =  ', i5, 2x,a8,/,                                 &
     &   ' 2ND AQUEOUS IC, NR <=0 IN AQUEOUS LOOP; = ',2i5)

!               write(c_out,*) neq,nrq,icq
!               write(c_out,*) ica1, ica2, icb1, icb2
!               write(c_out,*) nra1, nra2, nrb1, nrb2



! MAIN SOLVER FOR AQUEOUS IONS.
! OPTIONS FOR: NEUTRAL ION, SINGLE OR DOUBLE CATION, ANION.

! NEUTRAL AQUEOUS EQUILIBRIA:  GAS <-> AQUEOUS <-> NEUTRAL AQUEOUS.
!   THIS WORKS ONLY FOR A SINGLE CHAIN:  ONE NEUTRAL ION.

! Xa = Xg*Kh    X1=Xa*K1

            if(ica1.eq.0.and.icb1.eq.0) then

!                   TEST WRITE
!               if(c_kkw.gt.0) write(c_out,19003)
! 19003           format('NEUTRAL SPEC.')
!               if(c_kkw.gt.0) write(c_out,19004)c_tchem(icq), xc(1,icq)

!      do 16022 kk=1,c_kmax
       if(c_h2oliq(kk).gt.0) then
         gamma(kk) = 1.                                                 &
     &        /((rateq(kk,nrq)+1.)*rhdif(kk,nrh) + 1.)
         xc(kk, icq) = xc(kk,ic)*(rateq(kk,nrq)*rhdif(kk,nrh))          &
     &                 * gamma(kk)
         xc(kk, ich) = (xc(kk,ic)*rhdif(kk,nrh)) * gamma(kk)
         xc(kk, ic)  = xc(kk,ic) *                                      &
     &        (gamma(kk)*(c_h2oliq(kk)*avogadrl) )
       end if
16022  continue

!              TEST WRITE
!              if(c_kkw.gt.0) write(c_out,19004)c_tchem(icq), xc(1,icq)

            end if

! SINGLE CATION  - NOTE, SOLVE X1 FIRST, IN CASE Xgas, Xaq => 0.
!  Xg = Xt/ (1 + Kh*(1 + K1/H            ) )
!  Xa = Xg*Kh   X1=Xa*K1/H
!  dX1/dt = -(X1**2/(Xt*Kh*K1*H))*(1+Kh)
! NOTE:  SOLVE X1 FIRST, INCASE Xgas, Xaq =>0.
! ALSO:  Initially use XR(IC) = TOTAL GAS+AQUEOUS, in aq. units.
! Then solve for GAS at the end.

            if(ica1.gt.0.and.ica2.eq.0) then

!               TEST WRITE
!               if(c_kkw.gt.0) write(c_out,19005)
! 19005           format('SINGLE CATION')
!               if(c_kkw.gt.0) write(c_out,19004)c_tchem(icq), xc(1,icq)

!     do 16027 kk=1,c_kmax
       if(c_h2oliq(kk).gt.0.and.xc(kk,ic).gt.1.0D-40) then

         gamma(kk) = 1.                                                 &
     &        /((rateq(kk,nra1)*xhinv(kk) + 1.)*rhdif(kk,nrh) + 1.)

         xc(kk, ica1)  =                                                &
     &         (xc(kk,ic)*xhinv(kk)*rhdif(kk,nrh)*rateq(kk,nra1))       &
     &        *gamma(kk)

         xc(kk, ich) = (xc(kk,ic)*rhdif(kk,nrh)) * gamma(kk)

! ION SUM (alpha), d/dH ION SUM (beta):
         alpha(kk) = alpha(kk) - xc(kk,ica1)*c_ion(ica1)

         beta(kk) = beta(kk) - c_ion(ica1)*(                            &
     &   (1. + rhdif(kk,nrh))                                           &
     &   *(xc(kk,ica1)/xc(kk,ic))                                       &
     &   *(xc(kk,ica1)/(rhdif(kk,nrh)*rateq(kk,nra1)) )                 &
     &    )

! GAS SUM, converted to GAS units.
         xc(kk, ic)  = xc(kk,ic) *                                      &
     &        (gamma(kk)*(c_h2oliq(kk)*avogadrl) )

       end if
16027 continue
!              TEST WRITE
!              if(c_kkw.gt.0) write(c_out,19004)c_tchem(icq), xc(1,icq)

! DETAILED TEST WRITE
! 19011   format(8(1pe10.3))
!       if (c_kkw.gt.0) write(c_out,19011) xc(c_kkw,ica1)
!       if (c_kkw.gt.0) write(c_out,19011)
!    *    xc(c_kkw,ic), xhinv(c_kkw), rhdif(c_kkw,nrh)
!    *   , rateq(c_kkw,nra1), gamma(c_kkw)

!        if(c_kkw.gt.0) write(c_out,19011) xc(c_kkw,ich)
!        if(c_kkw.gt.0) write(c_out,19011) rhdif(c_kkw,nrh)
!    *      , gamma(c_kkw)

!        if(c_kkw.gt.0) write(c_out,19011) xc(c_kkw,ic)
!        if(c_kkw.gt.0) write(c_out,19011)  gamma(c_kkw)
!    *      , c_h2oliq(c_kkw),    avogadrl
! END TEST WRITES

            end if

! DOUBLE CATION
!  Xg = Xt/ (1 + Kh*(1 + K1/H*(1 + K2/H) ) )
!  Xa = Xg*Kh   X1=Xa*K1/H  X2=X1*K2/H
!  dX1/dH= X1/H - (X1**2/(Xt*Kh*K1*H) (2H(1+Kh)+Kh*K1)
!  dX2/dH = (X2**2/(Xt*Kh*K1*K2)(2H(1+Kh)+Kh*K1)

            if(ica1.gt.0.and.ica2.gt.0) then

!               TEST WRITE
!               if(c_kkw.gt.0) write(c_out,19006)
! 19006           format('DOUBLE CATION')
!               if(c_kkw.gt.0) write(c_out,19004)c_tchem(icq), xc(1,icq)

!     do 16031 kk=1,c_kmax
       if(c_h2oliq(kk).gt.0.and.xc(kk,ic).gt.1.0D-40) then

         gamma(kk) = 1.                                                 &
     &        /(((rateq(kk,nra2)*xhinv(kk) + 1.)                        &
     &           *rateq(kk,nra1)*xhinv(kk) + 1.)*rhdif(kk,nrh) + 1.)

         xc(kk, ica1)  =                                                &
     &         (xc(kk,ic)*xhinv(kk)*rhdif(kk,nrh)*rateq(kk,nra1))       &
     &        *gamma(kk)

         xc(kk, ica2) = xc(kk,ica1)*rateq(kk,nra2)*xhinv(kk)

         xc(kk, ich) = (xc(kk,ic)*rhdif(kk,nrh)) * gamma(kk)

! ION SUM (alpha), d/dH ION SUM (beta):
         alpha(kk) = alpha(kk) - xc(kk,ica1)*c_ion(ica1)                &
     &                         - xc(kk,ica2)*c_ion(ica2)

         beta(kk) = beta(kk)                                            &
     &    + c_ion(ica1) *xc(kk,ica1)*xhinv(kk)                          &
     &    - (2.*xc(kk,c_nhplus)*(1.+rhdif(kk,nrh))                      &
     &               + rhdif(kk,nrh)*rateq(kk,nra1)  )                  &
     &    * (                                                           &
     &    c_ion(ica1)*(xc(kk,ica1)/xc(kk,ic))                           &
     &    *(xc(kk,ica1)/(rhdif(kk,nrh)*rateq(kk,nra1)*xc(kk,c_nhplus)) )&
     &    + c_ion(ica2)*(xc(kk,ica2)/xc(kk,ic))                         &
     &   *(xc(kk,ica2)/(rhdif(kk,nrh)*rateq(kk,nra1)*rateq(kk,nra2)) )  &
     &    )




! GAS SUM, converted to GAS units.
         xc(kk, ic)  = xc(kk,ic) *                                      &
     &        (gamma(kk)*(c_h2oliq(kk)*avogadrl) )

       end if
16031 continue

!     TEST WRITE
!              if(c_kkw.gt.0) write(c_out,19004)c_tchem(icq), xc(1,icq)

! DETAILED TEST WRITE
!       if (c_kkw.gt.0) write(c_out,19011) xc(c_kkw,ica1)
!       if (c_kkw.gt.0) write(c_out,19011)
!    *    xc(c_kkw,ic), xhinv(c_kkw), rhdif(c_kkw,nrh)
!    *   , rateq(c_kkw,nra1), gamma(c_kkw)

!       if (c_kkw.gt.0) write(c_out,19011) xc(c_kkw,ica2)
!       if (c_kkw.gt.0) write(c_out,19011) rateq(c_kkw,nra2)
!    *    , xhinv(c_kkw)

!        if(c_kkw.gt.0) write(c_out,19011) xc(c_kkw,ich)
!        if(c_kkw.gt.0) write(c_out,19011) rhdif(c_kkw,nrh)
!    *    , gamma(c_kkw)

!        if(c_kkw.gt.0) write(c_out,19011) xc(c_kkw,ic)
!        if(c_kkw.gt.0) write(c_out,19011)  gamma(c_kkw)
!    *    , c_h2oliq(c_kkw),   avogadrl
! END TEST WRITE


            end if


! SINGLE ANION
! Xg = Xt/ (1 + Kh*(1 + R1/OH             ) )
! Xa = Xg*Kh    X1=Xa*K1/OH
! dX1/dH =  (OH/H)* (X1**2)/(Xt*Kh*K1)*(1+Kh)

            if(icb1.gt.0.and.icb2.eq.0) then

!               TEST WRITE
!               if(c_kkw.gt.0) write(c_out,19007)
! 19007           format('SINGLE ANION ')
!               if(c_kkw.gt.0) write(c_out,19004)c_tchem(icq), xc(1,icq)

!     do 16037 kk=1,c_kmax
       if(c_h2oliq(kk).gt.0.and.xc(kk,ic).gt.1.0D-40) then


         gamma(kk) = 1.                                                 &
     &        /((rateq(kk,nrb1)*xohinv(kk) + 1.)*rhdif(kk,nrh) + 1.)

         xc(kk, icb1)  =                                                &
     &         (xc(kk,ic)*xohinv(kk)*rhdif(kk,nrh)*rateq(kk,nrb1))      &
     &        *gamma(kk)

         xc(kk, ich) = (xc(kk,ic)*rhdif(kk,nrh)) * gamma(kk)

! ION SUM (alpha), d/dH ION SUM (beta):
         alpha(kk) = alpha(kk) - xc(kk,icb1)*c_ion(icb1)

         beta(kk) = beta(kk) + c_ion(icb1)*(                            &
     &   (xc(kk,c_nohmin)*xhinv(kk))   *  (1. + rhdif(kk,nrh))          &
     &   *(xc(kk,icb1)/xc(kk,ic))                                       &
     &   *(xc(kk,icb1)/(rhdif(kk,nrh)*rateq(kk,nrb1)) )                 &
     &    )

! GAS SUM, converted to GAS units.
         xc(kk, ic)  = xc(kk,ic) *                                      &
     &        (gamma(kk)*(c_h2oliq(kk)*avogadrl) )

       end if
16037 continue

!               TEST WRITE
!               if(c_kkw.gt.0) write(c_out,19004)c_tchem(icq), xc(1,icq)

            end if

! DOUBLE ANION
! Xg = Xt/ (1 + Kh*(1 + R1/OH*(1 + R2/OH) ) )
! Xa = Xg*Kh    X1=Xa*K1/OH   X2=X1*K2/OH
! dX1/dt= -X1/H + (X1**2/Xt*Kh*K1*H)*(2OH*(1+Kh)+Kh*K1) )
! dX2/dH =  (OH/H) * (X2**2/Xt*Kh*K1*K2)*(2OH(1+Kh)*Kh*K1)

            if(icb1.gt.0.and.icb2.gt.0) then

! TEST WRITE
!               if(c_kkw.gt.0) write(c_out,19008)
! 19008           format('DOUBLE ANION ')
!               if(c_kkw.gt.0) write(c_out,19004)c_tchem(icq), xc(1,icq)

!     do 16041 kk=1,c_kmax
       if(c_h2oliq(kk).gt.0.and.xc(kk,ic).gt.1.0D-40) then

         gamma(kk) = 1.                                                 &
     &        /(((rateq(kk,nrb2)*xohinv(kk) + 1.)                       &
     &           *rateq(kk,nrb1)*xohinv(kk) + 1.)*rhdif(kk,nrh) + 1.)

         xc(kk, icb1)  = xc(kk,ic) * (                                  &
     &         (          xohinv(kk)*rhdif(kk,nrh)*rateq(kk,nrb1))      &
     &        *gamma(kk)  )


         xc(kk, icb2) = xc(kk,icb1)*(rateq(kk,nrb2)*xohinv(kk))

         xc(kk, ich) = xc(kk,ic)*(rhdif(kk,nrh) * gamma(kk) )

! ION SUM (alpha), d/dH ION SUM (beta):
         alpha(kk) = alpha(kk) - xc(kk,icb1)*c_ion(icb1)                &
     &                         - xc(kk,icb2)*c_ion(icb2)

         beta(kk) = beta(kk)                                            &
     &    - c_ion(icb1) *xc(kk,icb1)*xhinv(kk)

         beta(kk) = beta(kk)                                            &
     &    + (2.*xc(kk,c_nohmin)*(1.+rhdif(kk,nrh))                      &
     &               + rhdif(kk,nrh)*rateq(kk,nrb1)  )                  &
     &    * (                                                           &
     &    c_ion(icb1)*(xc(kk,icb1)/xc(kk,ic))                           &
     &    *(xc(kk,icb1)/(rhdif(kk,nrh)*rateq(kk,nrb1)*xc(kk,c_nhplus)) )&
     &    + c_ion(icb2)*(xc(kk,icb2)/xc(kk,ic))                         &
     &                    *(xc(kk,c_nohmin)*xhinv(kk) )                 &
     &   *(xc(kk,icb2)/(rhdif(kk,nrh)*rateq(kk,nrb1)*rateq(kk,nrb2)) )  &
     &    )



! GAS SUM, converted to GAS units.
         xc(kk, ic)  = xc(kk,ic) *                                      &
     &        (gamma(kk)*(c_h2oliq(kk)*avogadrl) )


       end if
16041 continue

!              TEST WRITE
!              if(c_kkw.gt.0) write(c_out,19004)c_tchem(icq), xc(1,icq)

! DETAILED TEST WRITE
!       if (c_kkw.gt.0) write(c_out,19011) xc(c_kkw,icb1)
!       if (c_kkw.gt.0) write(c_out,19011)
!    *    xc(c_kkw,ic), xohinv(c_kkw), rhdif(c_kkw,nrh)
!    *  , rateq(c_kkw,nrb1), gamma(c_kkw)

!       if (c_kkw.gt.0) write(c_out,19011) xc(c_kkw,icb2)
!       if (c_kkw.gt.0) write(c_out,19011) rateq(c_kkw,nrb2)
!    *    , xohinv(c_kkw)

!        if(c_kkw.gt.0) write(c_out,19011) xc(c_kkw,ich)
!        if(c_kkw.gt.0) write(c_out,19011) rhdif(c_kkw,nrh)
!    *    , gamma(c_kkw)

!        if(c_kkw.gt.0) write(c_out,19011) xc(c_kkw,ic)
!        if(c_kkw.gt.0) write(c_out,19011)  gamma(c_kkw)
!    *    , c_h2oliq(c_kkw),    avogadrl
! END TEST WRITE

            end if

! 2006 ERROR CORRECTION - PROTECT AGAINST ZERO AQUEOUS - CUT
!     if(xc(1,ich).eq.0.) then
!       if(rhdif(1,nrh).gt.1.0e-10) xc(1,ich) = 1.0e-34
!     end if                        !if(xc(kk,ich).eq.0.) then

! DIAGNOSTIC TEST WRITE FOR H+ SOLVER
          if(c_kkw.gt.0) then
           write(c_out,1201) c_tchem(ic), alpha(c_kkw), beta (c_kkw)
          end if


!               TEST WRITE
!               write(c_out,*) xc( 1,icq),c_ion(icq),xc( 1,ic)
!               write(c_out,*) xc(1,ich), alpha(1),beta(1)

! END LOOP FOR AQUEOUS EQUILIBRIUM SPECIES
       end if


  100 continue

! ----------------------------------------------
! END OF LOOP TO CALCULATE AQUEOUS CONCENTRATIONS
! ----------------------------------------------
!
!
! -------------------------------
! CALCULATE H+ (AND OH-) FROM NEWTON-RAPHSON
! -------------------------------
!
! MODIFICATION FOR DIFFICULT CONVERGENCE: H+=geometric mean w/ prior H+
!   (To prevent oscillation with H+/SO2->HSO3-->SO4=.)

! ALSO:  INCREASE BETA BY RATIO:  ION RPRO/PRIOR ION SUM
! TO ACCOUNT FOR CHEM PRODUCTION ->H+ FEEDBACK.

!      do 16071 kk=1,c_kmax
       if(c_h2oliq(kk).gt.0) then
       if(rpro(kk,2).gt.rpro(kk,3).and.rpro(kk,3).gt.0)                 &
     &   beta(kk) = beta(kk)                                            &
     &       *(1.+rpro(kk,3)/(rpro(kk,2)-rpro(kk,3))  )
!
       if(beta(kk).ne.0) alpha(kk)  = alpha(kk)/beta(kk)
!      if(alpha(kk).lt.-0.9*xc(kk,c_nhplus))
!    *          alpha(kk)=-0.9*xc(kk,c_nhplus)
!      if(alpha(kk).gt.10*xc(kk,c_nhplus)) alpha(kk)=10.*xc(kk,c_nhplus)
!      xc(kk,c_nhplus) = xc(kk,c_nhplus) +  alpha(kk)
       if(alpha(kk).lt.-0.99*xc(kk,c_nhplus))                           &
     &        alpha(kk)=-0.9*xc(kk,c_nhplus)
       if(alpha(kk).gt.100*xc(kk,c_nhplus))                             &
     &        alpha(kk)=10.*xc(kk,c_nhplus)
       xc(kk,c_nhplus) =                                                &
     &        sqrt( xc(kk,c_nhplus) * (xc(kk,c_nhplus)+alpha(kk)) )
       if(xc(kk,c_nhplus).gt.0) then
           xc(kk,c_nohmin) = rateq(kk,1)/xc(kk,c_nhplus)
       end if

       end if
16071  continue


! ----------------------------------------------
! SUMMARY WRITE:   WRITE RESULTS OF ITERATION IF LPRT AND ACQUA>0.
! ----------------------------------------------

       if(c_kkw.gt.0) then
         if(c_h2oliq(c_kkw).gt.0) then
           write(c_out,1301)   c_h2oliq(c_kkw)
           acquacon = c_h2oliq( c_kkw)*avogadrl
           write(c_out,1303) acquacon
! 1303       format(/,'AQUATIC CONVERSION FACTOR:',
!    *          ' MOLE/LITER per MOLEC/CM3 =', 1pe10.3)
 1303       format( ' GAS SPECIES is gas only, molec/cm3. ',            &
     &      ' AQUEOUS moles/liter.',/,                                  &
     &       '                             CONVERSION= ', 1pe10.3)
           if(c_aqueous(1,2).gt.0) then
             write(c_out,1302) xc(c_kkw,c_aqueous(1,2))
           end if
 1301       format(/,'AQUEOUS CHEMISTRY ',/,'WATER (grams/cm3) =',      &
     &          1pe10.3)
 1302       format( ' [H+] (moles per liter) =',1pe10.3)

! NOTE:  GAS species given in molec/cm3; AQUEOUS in moles/liter
!        GAS is NOT YET GAS-AQ SUM.
           tsum = '     SUM'
           do 1300 ic=1,c_nchem2
            if(c_nequil(ic).gt.0)  then
              sum = xc(c_kkw,ic)
              do i=1,c_nequil(ic)
               sum = sum + xc(c_kkw,c_ncequil(ic,i))*acquacon
              end do
              write(c_out,1304) c_tchem(ic), xc(c_kkw,ic),              &
     &        ( c_tchem(c_ncequil(ic,i)),xc(c_kkw,c_ncequil(ic,i))      &
     &                                      ,i=1,c_nequil(ic) )         &
     &        ,tsum, sum
 1304          format(4(a8,1pe10.3),/,                                  &
     &        '         0.000E+00',3(a8,1pe10.3))
            end if
 1300      continue
!
          write(c_out,1306)
 1306      format(/,'HENRYS LAW RATES(+DIFFUSION ADJUSTMENT)',          &
     &       ' AND EQUILIBRIUM CONSTANTS:')
          if(c_nreach.gt.0) then
!           write(c_out,1307) ((c_treach(j,i),j=1,2),
!    *         rateh(c_kkw,i),rhdif(c_kkw,i),i=1,c_nreach)
            do i=1,c_nreach
             write(c_out,1307) (c_treach(j,i),j=1,2),                   &
     &         rateh(c_kkw,i),  rhdif(c_kkw,i)
            end do
 1307      format(a8,'=',a8,2x,2(1pe10.3))
          end if

          if(c_nreacq.gt.0) then
            write(c_out,1308) (c_treacq(j,1),j=1,3),                    &
     &       rateq(c_kkw,1), c_ion(c_aqueous(1,2))
 1308      format(a8,'=',a8,'+',a8,2x,e10.3,'    ION2=',i2)
          end if

          if(c_nreacq.gt.1) then
!           write(c_out,1308) ((c_treacq(j,i),j=1,3),
!    *       rateq(c_kkw,i), c_ion(c_aqueous(i,2))  ,i=2,c_nreacq)
            do i=2,c_nreacq
             write(c_out,1308) (c_treacq(j,i),j=1,3),                   &
     &       rateq(c_kkw,i), c_ion(c_aqueous(i,2))
            end do
          end if

         end if
       end if
! ----------------------------------------------
! END LOOP:  SUMMARY WRITE
! ----------------------------------------------


! END AQUASOLVE
 2000  return
      END

end module mod_cbmz_solve1
