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

      module mod_fudge

      implicit none

      contains

      subroutine lndfudge(fudge,ch,lndout,htgrid,iy,jx,char_lnd)

      implicit none
!
! Dummy arguments
!
      character(*) :: char_lnd
      logical :: fudge
      integer :: iy , jx
      character(1) , dimension(iy,jx) :: ch
      real(4) , dimension(iy,jx) :: htgrid , lndout
      intent (in) char_lnd , fudge , iy , jx
      intent (inout) ch , htgrid , lndout
!
! Local variables
!
      integer :: i , j
!
      if ( fudge ) then
        open (13,file=char_lnd,form='formatted')
        do i = iy , 1 , -1
          read (13,99001) (ch(i,j),j=1,jx)
        end do
        close (13)
        do j = 1 , jx
          do i = 1 , iy
            if ( ch(i,j)==' ' ) then
              lndout(i,j) = 15.
            else if ( ch(i,j)=='1' ) then
              lndout(i,j) = 1.
            else if ( ch(i,j)=='2' ) then
              lndout(i,j) = 2.
            else if ( ch(i,j)=='3' ) then
              lndout(i,j) = 3.
            else if ( ch(i,j)=='4' ) then
              lndout(i,j) = 4.
            else if ( ch(i,j)=='5' ) then
              lndout(i,j) = 5.
            else if ( ch(i,j)=='6' ) then
              lndout(i,j) = 6.
            else if ( ch(i,j)=='7' ) then
              lndout(i,j) = 7.
            else if ( ch(i,j)=='8' ) then
              lndout(i,j) = 8.
            else if ( ch(i,j)=='9' ) then
              lndout(i,j) = 9.
            else if ( ch(i,j)=='A' ) then
              lndout(i,j) = 10.
            else if ( ch(i,j)=='B' ) then
              lndout(i,j) = 11.
            else if ( ch(i,j)=='C' ) then
              lndout(i,j) = 12.
            else if ( ch(i,j)=='D' ) then
              lndout(i,j) = 13.
            else if ( ch(i,j)=='E' ) then
              lndout(i,j) = 14.
            else if ( ch(i,j)=='F' ) then
              lndout(i,j) = 15.
            else if ( ch(i,j)=='G' ) then
              lndout(i,j) = 16.
            else if ( ch(i,j)=='H' ) then
              lndout(i,j) = 17.
            else if ( ch(i,j)=='I' ) then
              lndout(i,j) = 18.
            else if ( ch(i,j)=='J' ) then
              lndout(i,j) = 19.
            else if ( ch(i,j)=='K' ) then
              lndout(i,j) = 20.
            else if ( nint(lndout(i,j))==0 ) then
!               ch(i,j) = 'X'
              ch(i,j) = ' '
            else
              write (*,*) 'LANDUSE MASK exceed the limit'
              stop
            end if
!_fix         if(nint(lndout(i,j)).eq.15) htgrid(i,j) = 0.0
            if ( htgrid(i,j)<0.1 .and. nint(lndout(i,j))==15 )        &
               & htgrid(i,j) = 0.0
          end do
        end do
      else
        do j = 1 , jx
          do i = 1 , iy
            if ( nint(lndout(i,j))==15 .or. nint(lndout(i,j))==0 ) then
              ch(i,j) = ' '
            else if ( nint(lndout(i,j))==1 ) then
              ch(i,j) = '1'
            else if ( nint(lndout(i,j))==2 ) then
              ch(i,j) = '2'
            else if ( nint(lndout(i,j))==3 ) then
              ch(i,j) = '3'
            else if ( nint(lndout(i,j))==4 ) then
              ch(i,j) = '4'
            else if ( nint(lndout(i,j))==5 ) then
              ch(i,j) = '5'
            else if ( nint(lndout(i,j))==6 ) then
              ch(i,j) = '6'
            else if ( nint(lndout(i,j))==7 ) then
              ch(i,j) = '7'
            else if ( nint(lndout(i,j))==8 ) then
              ch(i,j) = '8'
            else if ( nint(lndout(i,j))==9 ) then
              ch(i,j) = '9'
            else if ( nint(lndout(i,j))==10 ) then
              ch(i,j) = 'A'
            else if ( nint(lndout(i,j))==11 ) then
              ch(i,j) = 'B'
            else if ( nint(lndout(i,j))==12 ) then
              ch(i,j) = 'C'
            else if ( nint(lndout(i,j))==13 ) then
              ch(i,j) = 'D'
            else if ( nint(lndout(i,j))==14 ) then
              ch(i,j) = 'E'
            else if ( nint(lndout(i,j))==16 ) then
              ch(i,j) = 'G'
            else if ( nint(lndout(i,j))==17 ) then
              ch(i,j) = 'H'
            else if ( nint(lndout(i,j))==18 ) then
              ch(i,j) = 'I'
            else if ( nint(lndout(i,j))==19 ) then
              ch(i,j) = 'J'
            else if ( nint(lndout(i,j))==20 ) then
              ch(i,j) = 'K'
            else
              write (*,*) 'LANDUSE MASK' , nint(lndout(i,j)) ,        &
                         &'exceed the limit'
              stop
            end if
          end do
        end do
        open (13,file=char_lnd,form='formatted')
        do i = iy , 1 , -1
          write (13,99001) (ch(i,j),j=1,jx)
        end do
        close (13)
      end if
99001 format (132A1)
      end subroutine lndfudge

      subroutine texfudge(fudge,ch,texout,htgrid,iy,jx,char_tex)
      implicit none
!
! Dummy arguments
!
      character(*) :: char_tex
      logical :: fudge
      integer :: iy , jx
      character(1) , dimension(iy,jx) :: ch
      real(4) , dimension(iy,jx) :: htgrid , texout
      intent (in) char_tex , fudge , iy , jx
      intent (out) htgrid
      intent (inout) ch , texout
!
! Local variables
!
      integer :: i , j
!
      if ( fudge ) then
        open (13,file=char_tex,form='formatted')
        do i = iy , 1 , -1
          read (13,99001) (ch(i,j),j=1,jx)
        end do
        close (13)
        do j = 1 , jx
          do i = 1 , iy
            if ( ch(i,j)==' ' ) then
              texout(i,j) = 14.
            else if ( ch(i,j)=='1' ) then
              texout(i,j) = 1.
            else if ( ch(i,j)=='2' ) then
              texout(i,j) = 2.
            else if ( ch(i,j)=='3' ) then
              texout(i,j) = 3.
            else if ( ch(i,j)=='4' ) then
              texout(i,j) = 4.
            else if ( ch(i,j)=='5' ) then
              texout(i,j) = 5.
            else if ( ch(i,j)=='6' ) then
              texout(i,j) = 6.
            else if ( ch(i,j)=='7' ) then
              texout(i,j) = 7.
            else if ( ch(i,j)=='8' ) then
              texout(i,j) = 8.
            else if ( ch(i,j)=='9' ) then
              texout(i,j) = 9.
            else if ( ch(i,j)=='A' ) then
              texout(i,j) = 10.
            else if ( ch(i,j)=='B' ) then
              texout(i,j) = 11.
            else if ( ch(i,j)=='C' ) then
              texout(i,j) = 12.
            else if ( ch(i,j)=='D' ) then
              texout(i,j) = 13.
            else if ( ch(i,j)=='E' ) then
              texout(i,j) = 14.
            else if ( ch(i,j)=='F' ) then
              texout(i,j) = 15.
            else if ( ch(i,j)=='G' ) then
              texout(i,j) = 16.
            else if ( ch(i,j)=='H' ) then
              texout(i,j) = 17.
            else if ( nint(texout(i,j))==0 ) then
!             ch(i,j) = 'X'
              ch(i,j) = ' '
            else
              write (*,*) 'TEXTURE TYPE exceed the limit'
              stop
            end if
            if ( nint(texout(i,j))==14 ) htgrid(i,j) = 0.0
          end do
        end do
      else
        do j = 1 , jx
          do i = 1 , iy
            if ( nint(texout(i,j))==14 ) then
              ch(i,j) = ' '
            else if ( nint(texout(i,j))==1 ) then
              ch(i,j) = '1'
            else if ( nint(texout(i,j))==2 ) then
              ch(i,j) = '2'
            else if ( nint(texout(i,j))==3 ) then
              ch(i,j) = '3'
            else if ( nint(texout(i,j))==4 ) then
              ch(i,j) = '4'
            else if ( nint(texout(i,j))==5 ) then
              ch(i,j) = '5'
            else if ( nint(texout(i,j))==6 ) then
              ch(i,j) = '6'
            else if ( nint(texout(i,j))==7 ) then
              ch(i,j) = '7'
            else if ( nint(texout(i,j))==8 ) then
              ch(i,j) = '8'
            else if ( nint(texout(i,j))==9 ) then
              ch(i,j) = '9'
            else if ( nint(texout(i,j))==10 ) then
              ch(i,j) = 'A'
            else if ( nint(texout(i,j))==11 ) then
              ch(i,j) = 'B'
            else if ( nint(texout(i,j))==12 ) then
              ch(i,j) = 'C'
            else if ( nint(texout(i,j))==13 ) then
              ch(i,j) = 'D'
            else if ( nint(texout(i,j))==15 ) then
              ch(i,j) = 'F'
            else if ( nint(texout(i,j))==16 ) then
              ch(i,j) = 'G'
            else if ( nint(texout(i,j))==17 ) then
              ch(i,j) = 'H'
            else
              write (*,*) 'TEXTURE TYPE' , nint(texout(i,j)) ,          &
                         &'exceed the limit'
              stop
            end if
          end do
        end do
        open (13,file=char_tex,form='formatted')
        do i = iy , 1 , -1
          write (13,99001) (ch(i,j),j=1,jx)
        end do
        close (13)
      end if
99001 format (132A1)
      end subroutine texfudge

      subroutine lakeadj(lnduse,htgrid,xlat,xlon,imx,jmx)
 
      implicit none
!
! PARAMETER definitions
!
      real(4) , parameter :: zerie = 174. , zhuron = 177. ,             &
                           & zontar = 75. , zsup = 183. , zmich = 177.
!
! Dummy arguments
!
      integer :: imx , jmx
      real(4) , dimension(imx,jmx) :: htgrid , xlat , xlon
      integer , dimension(imx,jmx) :: lnduse
      intent (in) imx , jmx , lnduse , xlat , xlon
      intent (inout) htgrid
!
! Local variables
!
      integer :: i , j
      real(4) :: xx , yy
!
!     ****  ADJUST GREAT LAKE ELEVATION **** C
!
      do i = 1 , imx
        do j = 1 , jmx
          if ( lnduse(i,j)==14 ) then
            xx = xlon(i,j)
            yy = xlat(i,j)
            if ( yy<=43.2 .and. yy>=41.0 .and. xx<=-78.0 .and.          &
               & xx>=-84.0 ) then                       ! LAKE ERIE
              print * , '**** ADUJUSTING LAKE ERIE LEVEL ****'
              print * , '     NEW:' , zerie , '    OLD:' , htgrid(i,j) ,&
                  & i , j
              htgrid(i,j) = zerie
            else if ( yy<=46.4 .and. yy>=43.0 .and. xx<=-79.9 .and.     &
                    & yy>=-85.0 ) then                  ! LAKE HURON
              print * , '**** ADUJUSTING LAKE HURON LEVEL ****'
              print * , '     NEW:' , zhuron , '    OLD:' , htgrid(i,j) &
                  & , i , j
              htgrid(i,j) = zhuron
            else if ( yy<=44.5 .and. yy>=43.2 .and. xx<=-75.0 .and.     &
                    & yy>=-79.9 ) then                  ! LAKE ONTARIO
              print * , '**** ADUJUSTING LAKE ONTARIO LEVEL ****'
              print * , '     NEW:' , zontar , '    OLD:' , htgrid(i,j) &
                  & , i , j
              htgrid(i,j) = zontar
            else if ( yy<=49.4 .and. yy>=46.2 .and. xx<=-84.2 .and.     &
                    & xx>=-93.0 ) then                  ! LAKE SUPERIOR
              print * , '**** ADUJUSTING LAKE SUPERIOR LEVEL ****'
              print * , '     NEW:' , zsup , '    OLD:' , htgrid(i,j) , &
                  & i , j
              htgrid(i,j) = zsup
            else if ( yy<=46.2 .and. yy>=41.0 .and. xx<=-84.8 .and.     &
                    & xx>=-89.0 ) then                  ! LAKE MICHIGAN
              print * , '**** ADUJUSTING LAKE MICHIGAN LEVEL ****'
              print * , '     NEW:' , zmich , '    OLD:' , htgrid(i,j) ,&
                  & i , j
              htgrid(i,j) = zmich
            else
            end if
          end if
        end do
      end do
 
      end subroutine lakeadj

      end module mod_fudge
