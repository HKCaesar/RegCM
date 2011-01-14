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

      module mod_grid

      use m_realkinds
      use m_die
      use m_stdio
      use m_mall
      use m_zeit

      real(sp) , allocatable , dimension(:,:) :: coriol , dlat , dlon , &
           & msfx , snowcv , topogm , xlandu , xlat , xlon
      real(sp) , allocatable , dimension(:,:) :: pa , sst1 , sst2 ,     &
           & tlayer , za , ice1 , ice2
      real(sp) , allocatable , dimension(:,:) :: b3pd
      real(sp) , allocatable , dimension(:) :: dsigma , sigma2
      real(sp) , allocatable , dimension(:) :: sigmaf
      real(sp) :: delx , grdfac
      integer :: i0 , i1 , j0 , j1
      real(sp) :: lat0 , lat1 , lon0 , lon1

      contains

      subroutine init_grid(iy,jx,kz)
        implicit none
        integer , intent(in) :: iy , jx , kz
        integer :: ierr
        allocate(coriol(jx,iy), stat=ierr)
        if (ierr /= 0) call die('init_grid','allocate coriol',ierr)
        call mall_mci(coriol,'init_grid')
        allocate(dlat(jx,iy), stat=ierr)
        if (ierr /= 0) call die('init_grid','allocate dlat',ierr)
        call mall_mci(dlat,'init_grid')
        allocate(dlon(jx,iy), stat=ierr)
        if (ierr /= 0) call die('init_grid','allocate dlon',ierr)
        call mall_mci(dlon,'init_grid')
        allocate(msfx(jx,iy), stat=ierr)
        if (ierr /= 0) call die('init_grid','allocate msfx',ierr)
        call mall_mci(msfx,'init_grid')
        allocate(snowcv(jx,iy), stat=ierr)
        if (ierr /= 0) call die('init_grid','allocate snowcv',ierr)
        call mall_mci(snowcv,'init_grid')
        allocate(topogm(jx,iy), stat=ierr)
        if (ierr /= 0) call die('init_grid','allocate topogm',ierr)
        call mall_mci(topogm,'init_grid')
        allocate(xlandu(jx,iy), stat=ierr)
        if (ierr /= 0) call die('init_grid','allocate xlandu',ierr)
        call mall_mci(xlandu,'init_grid')
        allocate(xlat(jx,iy), stat=ierr)
        if (ierr /= 0) call die('init_grid','allocate xlat',ierr)
        call mall_mci(xlat,'init_grid')
        allocate(xlon(jx,iy), stat=ierr)
        if (ierr /= 0) call die('init_grid','allocate xlon',ierr)
        call mall_mci(xlon,'init_grid')
        allocate(pa(jx,iy), stat=ierr)
        if (ierr /= 0) call die('init_grid','allocate pa',ierr)
        call mall_mci(pa,'init_grid')
        allocate(sst1(jx,iy), stat=ierr)
        if (ierr /= 0) call die('init_grid','allocate sst1',ierr)
        call mall_mci(sst1,'init_grid')
        allocate(sst2(jx,iy), stat=ierr)
        if (ierr /= 0) call die('init_grid','allocate sst2',ierr)
        call mall_mci(sst2,'init_grid')
        allocate(tlayer(jx,iy), stat=ierr)
        if (ierr /= 0) call die('init_grid','allocate tlayer',ierr)
        call mall_mci(tlayer,'init_grid')
        allocate(za(jx,iy), stat=ierr)
        if (ierr /= 0) call die('init_grid','allocate za',ierr)
        call mall_mci(za,'init_grid')
        allocate(ice1(jx,iy), stat=ierr)
        if (ierr /= 0) call die('init_grid','allocate ice1',ierr)
        call mall_mci(ice1,'init_grid')
        allocate(ice2(jx,iy), stat=ierr)
        if (ierr /= 0) call die('init_grid','allocate ice2',ierr)
        call mall_mci(ice2,'init_grid')
        allocate(b3pd(jx,iy), stat=ierr)
        if (ierr /= 0) call die('init_grid','allocate b3pd',ierr)
        call mall_mci(b3pd,'init_grid')
        allocate(dsigma(kz), stat=ierr)
        if (ierr /= 0) call die('init_grid','allocate dsigma',ierr)
        call mall_mci(dsigma,'init_grid')
        allocate(sigma2(kz), stat=ierr)
        if (ierr /= 0) call die('init_grid','allocate sigma2',ierr)
        call mall_mci(sigma2,'init_grid')
        allocate(sigmaf(kz+1), stat=ierr)
        if (ierr /= 0) call die('init_grid','allocate sigmaf',ierr)
        call mall_mci(sigmaf,'init_grid')

        call read_domain

      end subroutine init_grid

      subroutine free_grid
        implicit none
        call mall_mco(coriol,'init_grid')
        deallocate(coriol)
        call mall_mco(dlat,'init_grid')
        deallocate(dlat)
        call mall_mco(dlon,'init_grid')
        deallocate(dlon)
        call mall_mco(msfx,'init_grid')
        deallocate(msfx)
        call mall_mco(snowcv,'init_grid')
        deallocate(snowcv)
        call mall_mco(topogm,'init_grid')
        deallocate(topogm)
        call mall_mco(xlandu,'init_grid')
        deallocate(xlandu)
        call mall_mco(xlat,'init_grid')
        deallocate(xlat)
        call mall_mco(xlon,'init_grid')
        deallocate(xlon)
        call mall_mco(pa,'init_grid')
        deallocate(pa)
        call mall_mco(sst1,'init_grid')
        deallocate(sst1)
        call mall_mco(sst2,'init_grid')
        deallocate(sst2)
        call mall_mco(tlayer,'init_grid')
        deallocate(tlayer)
        call mall_mco(za,'init_grid')
        deallocate(za)
        call mall_mco(ice1,'init_grid')
        deallocate(ice1)
        call mall_mco(ice2,'init_grid')
        deallocate(ice2)
        call mall_mco(b3pd,'init_grid')
        deallocate(b3pd)
        call mall_mco(dsigma,'init_grid')
        deallocate(dsigma)
        call mall_mco(sigma2,'init_grid')
        deallocate(sigma2)
        call mall_mco(sigmaf,'init_grid')
        deallocate(sigmaf)
      end subroutine free_grid

      subroutine read_domain
        use netcdf
        use mod_dynparam
        implicit none
        integer :: istatus
        integer :: incin
        integer :: idimid
        integer :: ivarid
        character(256) :: fname
        integer :: jx_in , iy_in , kz_in , k

        call zeit_ci('readdom')
        fname = trim(dirter)//pthsep//trim(domname)//'_DOMAIN000.nc'

        istatus = nf90_open(fname, nf90_nowrite, incin)
        call check_ok('Error open domain file '//trim(fname))

        istatus = nf90_inq_dimid(incin, "iy", idimid)
        call check_ok('Error searching iy dimension')
        istatus = nf90_inquire_dimension(incin, idimid, len=iy_in)
        call check_ok('Error reading iy dimension')
        istatus = nf90_inq_dimid(incin, "jx", idimid)
        call check_ok('Error searching jx dimension')
        istatus = nf90_inquire_dimension(incin, idimid, len=jx_in)
        call check_ok('Error reading jx dimension')
        istatus = nf90_inq_dimid(incin, "kz", idimid)
        call check_ok('Error searching kz dimension')
        istatus = nf90_inquire_dimension(incin, idimid, len=kz_in)
        call check_ok('Error reading kz dimension')

        if ( iy_in/=iy .or. jx_in/=jx .or. kz_in/=kz+1 ) then
          write(stderr,*) 'IMPROPER DIMENSION SPECIFICATION'
          write(stderr,*) '  namelist  : ' , iy , jx , kz
          write(stderr,*) '  DOMAIN    : ' , iy_in , jx_in , kz_in
          call die('read_domain','Dimension mismatch',1)
        end if

        istatus = nf90_get_att(incin, NF90_GLOBAL,"grid_factor", &
                       &       grdfac)
        call check_ok('Error reading grid_factor attribute')

        istatus = nf90_inq_varid(incin, "topo", ivarid)
        call check_ok('Error searching topo variable')
        istatus = nf90_get_var(incin, ivarid, topogm)
        call check_ok('Error reading topo variable')
        istatus = nf90_inq_varid(incin, "landuse", ivarid)
        call check_ok('Error searching landuse variable')
        istatus = nf90_get_var(incin, ivarid, xlandu)
        call check_ok('Error reading landuse variable')
        istatus = nf90_inq_varid(incin, "xlat", ivarid)
        call check_ok('Error searching xlat variable')
        istatus = nf90_get_var(incin, ivarid, xlat)
        call check_ok('Error reading xlat variable')
        istatus = nf90_inq_varid(incin, "xlon", ivarid)
        call check_ok('Error searching xlon variable')
        istatus = nf90_get_var(incin, ivarid, xlon)
        call check_ok('Error reading xlon variable')
        istatus = nf90_inq_varid(incin, "dlat", ivarid)
        call check_ok('Error searchin dlat variable')
        istatus = nf90_get_var(incin, ivarid, dlat)
        call check_ok('Error reading dlat variable')
        istatus = nf90_inq_varid(incin, "dlon", ivarid)
        call check_ok('Error searching dlon variable')
        istatus = nf90_get_var(incin, ivarid, dlon)
        call check_ok('Error reading dlon variable')
        istatus = nf90_inq_varid(incin, "xmap", ivarid)
        call check_ok('Error searching xmap variable')
        istatus = nf90_get_var(incin, ivarid, msfx)
        call check_ok('Error reading xmap variable')
        istatus = nf90_inq_varid(incin, "sigma", ivarid)
        call check_ok('Error searching sigma variable')
        istatus = nf90_get_var(incin, ivarid, sigmaf)
        call check_ok('Error reading sigma variable')

        istatus = nf90_close(incin)
        call check_ok('Error closing Domain file '//trim(fname))
!
        do k = 1 , kz
          sigma2(k) = 0.5*(sigmaf(k+1)+sigmaf(k))
          dsigma(k) = sigmaf(k+1) - sigmaf(k)
        end do

        call zeit_co('readdom')
      contains
!
        subroutine check_ok(message)
          use netcdf
          implicit none
          character(*) :: message
          if (istatus /= nf90_noerr) then
            call die('read_domain',message,1, &
                     nf90_strerror(istatus),istatus)
          end if
        end subroutine check_ok
!
      end subroutine read_domain
!
      end module mod_grid
