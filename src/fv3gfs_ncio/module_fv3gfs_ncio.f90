module module_fv3gfs_ncio
! module for reading/writing netcdf global lat/lon grid files output by FV3GFS
! jeff whitaker 201909

  use netcdf

  implicit none
  private

  type Variable
     integer varid ! netCDF variable ID
     integer ndims ! number of dimensions
     integer dtype ! netCDF data type
     integer natts ! number of attributes
     integer deflate_level ! compression level (if > 0)
     logical shuffle  ! shuffle filter?
     logical hasunlim ! has an unlimited dim?
     character(len=nf90_max_name) :: name ! variable name
     integer, allocatable, dimension(:) :: dimids ! netCDF dimension IDs
     ! indices into Dataset%dimensions for associated dimensions.
     integer, allocatable, dimension(:) :: dimindxs 
     ! names of associated dimensions.
     character(len=nf90_max_name), allocatable, dimension(:) :: dimnames 
     ! current dimension lengths (updated after every write_vardata call)
     integer, allocatable, dimension(:) :: dimlens
  end type Variable   
  type Dimension 
     integer dimid ! netCDF dimension ID
     integer len ! dimension length (updated after every write_vardata call)
     logical isunlimited ! unlimited?
     character(len=nf90_max_name) :: name ! name of dimension
  end type Dimension
  type Dataset
     integer :: ncid ! netCDF ID.
     integer :: nvars ! number of variables in dataset
     integer :: ndims ! number of dimensions in dataset
     integer :: natts ! number of dataset (global) attributes
     integer :: nunlimdim ! dimension ID for unlimited dimension
     character(len=500) filename ! netCDF filename
     ! array of Variable instances
     type(Variable), allocatable, dimension(:) :: variables
     ! array of Dimension instances
     type(Dimension), allocatable, dimension(:) :: dimensions
  end type Dataset

  interface read_vardata
      module procedure read_vardata_1d_r4, read_vardata_2d_r4, read_vardata_3d_r4,&
      read_vardata_4d_r4, read_vardata_1d_r8, read_vardata_2d_r8, read_vardata_3d_r8,&
      read_vardata_4d_r8, read_vardata_1d_int, read_vardata_2d_int, &
      read_vardata_3d_int, read_vardata_4d_int,&
      read_vardata_5d_r4, read_vardata_5d_r8, read_vardata_5d_int 
  end interface

  interface write_vardata
      module procedure write_vardata_1d_r4, write_vardata_2d_r4, write_vardata_3d_r4,&
      write_vardata_4d_r4, write_vardata_1d_r8, write_vardata_2d_r8, write_vardata_3d_r8,&
      write_vardata_4d_r8, write_vardata_1d_int, write_vardata_2d_int, &
      write_vardata_3d_int, write_vardata_4d_int, &
      write_vardata_5d_int, write_vardata_5d_r4, write_vardata_5d_r8
  end interface

  interface read_attribute
      module procedure read_attribute_r4_scalar, read_attribute_int_scalar,&
      read_attribute_r8_scalar, read_attribute_r4_1d,&
      read_attribute_int_1d, read_attribute_r8_1d, read_attribute_char
  end interface

  interface write_attribute
      module procedure write_attribute_r4_scalar, write_attribute_int_scalar,&
      write_attribute_r8_scalar, write_attribute_r4_1d,&
      write_attribute_int_1d, write_attribute_r8_1d, write_attribute_char
  end interface

  public :: open_dataset, create_dataset, close_dataset, Dataset, Variable, Dimension, &
  read_vardata, read_attribute, write_vardata, write_attribute, get_ndim, &
  get_nvar, get_var, get_dim, quantized, get_idate_from_time_units,&
  get_time_units_from_idate

  contains

  subroutine nccheck(status)
    ! check return code, print error message 
    implicit none
    integer, intent (in) :: status
    if (status /= nf90_noerr) then
      write(0,*) status, trim(nf90_strerror(status))
      stop "stopped"
    end if
  end subroutine nccheck

  function get_dim(dset, dimname) result(dim)
    type(Dataset) :: dset
    type(Dimension) :: dim
    character(len=*), intent(in) :: dimname
    integer ndim
    ndim = get_ndim(dset, dimname)
    dim = dset%dimensions(ndim)
  end function get_dim

  integer function get_ndim(dset, dimname)
    ! get dimension index given name
    type(Dataset), intent(in) :: dset
    character(len=*), intent(in) :: dimname
    logical foundit
    integer ndim
    get_ndim = -1
    do ndim=1,dset%ndims
       if (trim(dset%dimensions(ndim)%name) == trim(dimname)) then 
          get_ndim = ndim
          exit
       endif
    enddo
  end function get_ndim

  function get_var(dset, varname) result (var)
    type(Dataset) :: dset
    type(Variable) :: var
    character(len=*) :: varname
    integer nvar
    nvar = get_nvar(dset, varname)
    var = dset%variables(nvar)
  end function get_var

  integer function get_nvar(dset,varname)
    ! get variable index given name
    type(Dataset), intent(in) :: dset
    character(len=*), intent(in) :: varname
    logical foundit
    integer nvar
    get_nvar = -1
    do nvar=1,dset%nvars
       if (trim(dset%variables(nvar)%name) == trim(varname)) then 
          get_nvar = nvar
          exit
       endif
    enddo
  end function get_nvar

  subroutine set_varunlimdimlens_(dset,errcode)
    ! reset dimension length (dimlens) for unlim dim for all variables
    type(Dataset), intent(inout) :: dset
    integer, intent(out), optional :: errcode
    integer ndim,n,nvar,ncerr
    logical return_errcode
    if(present(errcode)) then
       return_errcode=.true.
       errcode = 0
    else
       return_errcode=.false.
    endif
    ! loop over all vars
    do nvar=1,dset%nvars
       ! does var have unlim dimension?
       if (dset%variables(nvar)%hasunlim) then
          ! loop over all var dimensions
          do ndim=1,dset%variables(nvar)%ndims
             n = dset%variables(nvar)%dimindxs(ndim)
             ! n is the dimension index for this variable dimension
             ! if this dim is unlimited, update dimlens entry
             if (dset%dimensions(n)%isunlimited) then
                ncerr = nf90_inquire_dimension(dset%ncid,&
                                               dset%dimensions(n)%dimid, &
                                               len=dset%variables(nvar)%dimlens(ndim))
                if (return_errcode) then
                   errcode=ncerr
                   return
                else
                   call nccheck(ncerr)
                endif
                ! also update len attribute of Dimension object
                dset%dimensions(n)%len = dset%variables(nvar)%dimlens(ndim)
             endif
          enddo
       endif
    enddo
  end subroutine set_varunlimdimlens_
 
  function open_dataset(filename,errcode) result(dset)
    ! open existing dataset, create dataset object for reading netcdf file 
    ! if optional error return code errcode is not specified,
    ! program will stop if a nonzero error code returned by the netcdf lib.
    implicit none
    character(len=*), intent(in) :: filename
    type(Dataset) :: dset
    integer, intent(out), optional :: errcode
    integer ncerr,nunlimdim
    integer ndim,nvar,n
    logical return_errcode
    if(present(errcode)) then
       return_errcode=.true.
       errcode = 0
    else
       return_errcode=.false.
    endif
    ! open netcdf file, get info, populate Dataset object.
    ncerr = nf90_open(trim(filename), NF90_NOWRITE, ncid=dset%ncid)
    if (return_errcode) then
       errcode=ncerr
       if (ncerr /= 0) return
    else
       call nccheck(ncerr)
    endif
    ncerr = nf90_inquire(dset%ncid, dset%ndims, dset%nvars, dset%natts, nunlimdim)
    if (return_errcode) then
       errcode=ncerr
       if (ncerr /= 0) return
    else
       call nccheck(ncerr)
    endif
    dset%filename = trim(filename)
    allocate(dset%variables(dset%nvars))
    allocate(dset%dimensions(dset%ndims))
    do ndim=1,dset%ndims
       dset%dimensions(ndim)%dimid = ndim
       ncerr = nf90_inquire_dimension(dset%ncid, ndim, name=dset%dimensions(ndim)%name, &
                                      len=dset%dimensions(ndim)%len)
       if (return_errcode) then
          errcode=ncerr
          if (ncerr /= 0) return
       else
          call nccheck(ncerr)
       endif
       if (ndim == nunlimdim) then
          dset%dimensions(ndim)%isunlimited = .true.
       else
          dset%dimensions(ndim)%isunlimited = .false.
       endif
    enddo
    do nvar=1,dset%nvars
       dset%variables(nvar)%hasunlim = .false.
       dset%variables(nvar)%varid = nvar
       ncerr = nf90_inquire_variable(dset%ncid, nvar,&
                                     name=dset%variables(nvar)%name,&
                                     natts=dset%variables(nvar)%natts,&
                                     xtype=dset%variables(nvar)%dtype,&
                                     ndims=dset%variables(nvar)%ndims)
       if (return_errcode) then
          errcode=ncerr
          if (ncerr /= 0) return
       else
          call nccheck(ncerr)
       endif
       allocate(dset%variables(nvar)%dimids(dset%variables(nvar)%ndims))
       allocate(dset%variables(nvar)%dimindxs(dset%variables(nvar)%ndims))
       allocate(dset%variables(nvar)%dimlens(dset%variables(nvar)%ndims))
       allocate(dset%variables(nvar)%dimnames(dset%variables(nvar)%ndims))
       ncerr = nf90_inquire_variable(dset%ncid, nvar,&
                                     dimids=dset%variables(nvar)%dimids,&
                                     deflate_level=dset%variables(nvar)%deflate_level,&
                                     shuffle=dset%variables(nvar)%shuffle)
       if (return_errcode) then
          errcode=ncerr
          if (ncerr /= 0) return
       else
          call nccheck(ncerr)
       endif
       do ndim=1,dset%variables(nvar)%ndims
          do n=1,dset%ndims
            if (dset%variables(nvar)%dimids(ndim) == dset%dimensions(n)%dimid) then
               exit
            endif
          enddo
          dset%variables(nvar)%dimindxs(ndim) = n
          dset%variables(nvar)%dimlens(ndim) = dset%dimensions(n)%len
          dset%variables(nvar)%dimnames(ndim) = dset%dimensions(n)%name
          if (dset%dimensions(n)%isunlimited) then
             dset%variables(nvar)%hasunlim = .true.
          endif
       enddo
    enddo
  end function open_dataset

  function create_dataset(filename, dsetin, copy_vardata, errcode) result(dset)
    ! create new dataset, using an existing dataset object to define
    ! variables, dimensions and attributes.
    ! If copy_vardata=T, all variable data (not just coordinate
    ! variable data) is copied. Default is F (only coord var data
    ! copied).
    ! if optional error return code errcode is not specified,
    ! program will stop if a nonzero error code returned by the netcdf lib.
    implicit none
    character(len=*), intent(in) :: filename
    character(len=nf90_max_name) :: attname, varname
    logical, intent(in), optional :: copy_vardata
    type(Dataset) :: dset
    type(Dataset), intent(in) :: dsetin
    integer, intent(out), optional :: errcode
    integer ncerr
    integer ndim,nvar,n,ishuffle,natt
    logical copyd, coordvar
    real(8), allocatable, dimension(:) :: values_1d
    real(8), allocatable, dimension(:,:) :: values_2d
    real(8), allocatable, dimension(:,:,:) :: values_3d
    real(8), allocatable, dimension(:,:,:,:) :: values_4d
    real(8), allocatable, dimension(:,:,:,:,:) :: values_5d
    integer, allocatable, dimension(:) :: ivalues_1d
    integer, allocatable, dimension(:,:) :: ivalues_2d
    integer, allocatable, dimension(:,:,:) :: ivalues_3d
    integer, allocatable, dimension(:,:,:,:) :: ivalues_4d
    integer, allocatable, dimension(:,:,:,:,:) :: ivalues_5d
    logical return_errcode
    if(present(errcode)) then
       return_errcode=.true.
       errcode = 0
    else
       return_errcode=.false.
    endif
    if (present(copy_vardata)) then
       copyd = .true.  ! copy all variable data
    else
       copyd = .false. ! only copy coordinate variable data
    endif
    ! create netcdf file
    ncerr = nf90_create(trim(filename), &
            cmode=IOR(IOR(NF90_CLOBBER,NF90_NETCDF4),NF90_CLASSIC_MODEL), &
            !cmode=IOR(NF90_CLOBBER,NF90_NETCDF4), &
            ncid=dset%ncid)
    if (return_errcode) then
       errcode=ncerr
       if (ncerr /= 0) return
    else
       call nccheck(ncerr)
    endif
    ! copy global attributes
    do natt=1,dsetin%natts
       ncerr = nf90_inq_attname(dsetin%ncid, NF90_GLOBAL, natt, attname)
       if (return_errcode) then
          errcode=ncerr
          if (ncerr /= 0) return
       else
          call nccheck(ncerr)
       endif
       ncerr = nf90_copy_att(dsetin%ncid, NF90_GLOBAL, attname, dset%ncid, NF90_GLOBAL)
       if (return_errcode) then
          errcode=ncerr
          if (ncerr /= 0) return
       else
          call nccheck(ncerr)
       endif
    enddo
    dset%natts = dsetin%natts
    dset%filename = trim(filename)
    dset%ndims = dsetin%ndims
    dset%nvars = dsetin%nvars
    allocate(dset%variables(dsetin%nvars))
    allocate(dset%dimensions(dsetin%ndims))
    ! create dimensions
    do ndim=1,dsetin%ndims
       if (dsetin%dimensions(ndim)%isunlimited) then
          ncerr = nf90_def_dim(dset%ncid, trim(dsetin%dimensions(ndim)%name), &
                  NF90_UNLIMITED, &
                  dset%dimensions(ndim)%dimid)
          if (return_errcode) then
             errcode=ncerr
             if (ncerr /= 0) return
          else
             call nccheck(ncerr)
          endif
          dset%dimensions(ndim)%isunlimited = .true.
          dset%nunlimdim = ndim
          dset%dimensions(ndim)%len = 0
          dset%dimensions(ndim)%name = trim(dsetin%dimensions(ndim)%name)
       else
          ncerr = nf90_def_dim(dset%ncid, trim(dsetin%dimensions(ndim)%name),&
                  dsetin%dimensions(ndim)%len, &
                  dset%dimensions(ndim)%dimid)
          if (return_errcode) then
             errcode=ncerr
             if (ncerr /= 0) return
          else
             call nccheck(ncerr)
          endif
          dset%dimensions(ndim)%len = dsetin%dimensions(ndim)%len
          dset%dimensions(ndim)%isunlimited = .false.
          dset%dimensions(ndim)%name = trim(dsetin%dimensions(ndim)%name)
       endif
    enddo
    ! create variables
    do nvar=1,dsetin%nvars
       dset%variables(nvar)%hasunlim = .false.
       dset%variables(nvar)%ndims = dsetin%variables(nvar)%ndims
       allocate(dset%variables(nvar)%dimids(dset%variables(nvar)%ndims))
       allocate(dset%variables(nvar)%dimindxs(dset%variables(nvar)%ndims))
       allocate(dset%variables(nvar)%dimnames(dset%variables(nvar)%ndims))
       allocate(dset%variables(nvar)%dimlens(dset%variables(nvar)%ndims))
       do ndim=1,dset%variables(nvar)%ndims
          do n=1,dset%ndims
            if (trim(dsetin%variables(nvar)%dimnames(ndim)) == &
                trim(dset%dimensions(n)%name)) then
               exit
            endif
          enddo
          dset%variables(nvar)%dimindxs(ndim) = n
          dset%variables(nvar)%dimids(ndim) = dset%dimensions(n)%dimid
          dset%variables(nvar)%dimlens(ndim) = dset%dimensions(n)%len
          dset%variables(nvar)%dimnames(ndim) = dset%dimensions(n)%name
          if (dset%dimensions(n)%isunlimited) then
             dset%variables(nvar)%hasunlim = .true.
          endif
       enddo
       dset%variables(nvar)%name = dsetin%variables(nvar)%name
       dset%variables(nvar)%dtype = dsetin%variables(nvar)%dtype
       ncerr = nf90_def_var(dset%ncid, &
                            trim(dset%variables(nvar)%name),&
                            dset%variables(nvar)%dtype, &
                            dset%variables(nvar)%dimids, &
                            dset%variables(nvar)%varid)
       if (return_errcode) then
          errcode=ncerr
          if (ncerr /= 0) return
       else
          call nccheck(ncerr)
       endif
       if (dsetin%variables(nvar)%deflate_level > 0) then
          if (dsetin%variables(nvar)%shuffle) then
            ishuffle=1
          else
            ishuffle=0
          endif
          ncerr = nf90_def_var_deflate(dset%ncid, dset%variables(nvar)%varid,&
                  ishuffle,1,dsetin%variables(nvar)%deflate_level)
          if (return_errcode) then
             errcode=ncerr
             if (ncerr /= 0) return
          else
             call nccheck(ncerr)
          endif
          dset%variables(nvar)%shuffle = dsetin%variables(nvar)%shuffle
          dset%variables(nvar)%deflate_level = &
          dsetin%variables(nvar)%deflate_level
       endif
       ! copy variable attributes
       do natt=1,dsetin%variables(nvar)%natts
          ncerr = nf90_inq_attname(dsetin%ncid, dsetin%variables(nvar)%varid, natt, attname)
          if (return_errcode) then
             errcode=ncerr
             if (ncerr /= 0) return
          else
             call nccheck(ncerr)
          endif
          ncerr = nf90_copy_att(dsetin%ncid, dsetin%variables(nvar)%varid, attname, dset%ncid, dset%variables(nvar)%varid)
          if (return_errcode) then
             errcode=ncerr
            if (ncerr /= 0) return
          else
             call nccheck(ncerr)
          endif
       enddo
    enddo
    ncerr = nf90_enddef(dset%ncid)
    if (return_errcode) then
       errcode=ncerr
       if (ncerr /= 0) return
    else
       call nccheck(ncerr)
    endif
    ! copy variable data 
    ! assumes data is real (32 or 64 bit), or integer (16 or 32 bit) and 1-4d.
    do nvar=1,dsetin%nvars
       varname = trim(dsetin%variables(nvar)%name)
       ! is this variable a coordinate variable?
       coordvar = .false.
       if (trim(varname) == 'lats' .or. trim(varname) == 'lons' .or. &
           trim(varname) == 'lat'  .or. trim(varname) == 'lon') then
          coordvar = .true.
       else
          do ndim=1,dset%ndims
             if (trim(varname) == trim(dset%dimensions(ndim)%name)) then
                coordvar = .true.
             endif
          enddo
       endif
       ! if copy_data flag not given, and not a coordinate var,
       ! skip to next var.
       if (.not. coordvar .and. .not. copyd) cycle
       ! real variable
       if (dsetin%variables(nvar)%dtype == NF90_FLOAT .or.&
           dsetin%variables(nvar)%dtype == NF90_DOUBLE) then
          if (dsetin%variables(nvar)%ndims == 1) then
             call read_vardata(dsetin, varname, values_1d)
             call write_vardata(dset, varname, values_1d)
          else if (dsetin%variables(nvar)%ndims == 2) then
             call read_vardata(dsetin, varname, values_2d)
             call write_vardata(dset, varname, values_2d)
          else if (dsetin%variables(nvar)%ndims == 3) then
             call read_vardata(dsetin, varname, values_3d)
             call write_vardata(dset, varname, values_3d)
          else if (dsetin%variables(nvar)%ndims == 4) then
             call read_vardata(dsetin, varname, values_4d)
             call write_vardata(dset, varname, values_4d)
          else if (dsetin%variables(nvar)%ndims == 5) then
             call read_vardata(dsetin, varname, values_5d)
             call write_vardata(dset, varname, values_5d)
          endif
       ! integer var
       elseif (dsetin%variables(nvar)%dtype == NF90_INT .or.&
               dsetin%variables(nvar)%dtype == NF90_SHORT) then
          if (dsetin%variables(nvar)%ndims == 1) then
             call read_vardata(dsetin, varname, ivalues_1d)
             call write_vardata(dset, varname, ivalues_1d)
          else if (dsetin%variables(nvar)%ndims == 2) then
             call read_vardata(dsetin, varname, ivalues_2d)
             call write_vardata(dset, varname, ivalues_2d)
          else if (dsetin%variables(nvar)%ndims == 3) then
             call read_vardata(dsetin, varname, ivalues_3d)
             call write_vardata(dset, varname, ivalues_3d)
          else if (dsetin%variables(nvar)%ndims == 4) then
             call read_vardata(dsetin, varname, ivalues_4d)
             call write_vardata(dset, varname, ivalues_4d)
          else if (dsetin%variables(nvar)%ndims == 5) then
             call read_vardata(dsetin, varname, ivalues_5d)
             call write_vardata(dset, varname, ivalues_5d)
          endif
       else
          print *,'not copying variable ',trim(adjustl(varname)),&
                  ' (unsupported data type or rank)'
       endif
    enddo
  end function create_dataset
 
  subroutine close_dataset(dset,errcode)
    ! close netcdf file, deallocate members of dataset object.
    ! if optional error return code errcode is not specified,
    ! program will stop if a nonzero error code returned by the netcdf lib.
    type(Dataset), intent(inout) :: dset
    integer, intent(out), optional :: errcode
    integer ncerr, nvar
    logical return_errcode
    if(present(errcode)) then
       return_errcode=.true.
       errcode = 0
    else
       return_errcode=.false.
    endif
    ncerr = nf90_close(ncid=dset%ncid)
    if (return_errcode) then
       errcode=ncerr
       if (ncerr /= 0) return
    else
       call nccheck(ncerr)
    endif
    do nvar=1,dset%nvars
       deallocate(dset%variables(nvar)%dimids)
       deallocate(dset%variables(nvar)%dimindxs)
       deallocate(dset%variables(nvar)%dimlens)
       deallocate(dset%variables(nvar)%dimnames)
    enddo
    deallocate(dset%variables,dset%dimensions)
  end subroutine close_dataset
 
  !subroutine read_vardata(dset,varname,values,nslice,errcode)
  ! read data from variable varname in dataset dset, return in it array values.
  ! dset:    Input dataset instance returned by open_dataset/create_dataset.
  ! varname: Input string name of variable.
  ! values:  Array to hold variable data.  Must be
  !          an allocatable array with same rank 
  !          as variable varname (or 1 dimension less).
  ! nslice:  optional index along last dimension of 
  !          variable if rank of values is rank of 
  !          variable minus 1.  Default is 1.  
  ! errcode: optional error return code.  If not specified,
  !          program will stop if a nonzero error code returned
  !          from netcdf library.

  !subroutine write_vardata(dset,varname,values,nslice,errcode)
  ! write data (in array values) to variable varname in dataset dset.
  ! dset:    Input dataset instance returned by open_dataset/create_dataset.
  ! varname: Input string name of variable.
  ! values:  Array with variable data.  Must be
  !          an allocatable array with same rank 
  !          as variable varname (or 1 dimension less).
  ! nslice:  optional index along last dimension of 
  !          variable if rank of values is rank of 
  !          variable minus 1.  Default is 1.  
  ! errcode: optional error return code.  If not specified,
  !          program will stop if a nonzero error code returned
  !          from netcdf library.

  !subroutine read_attribute(dset, attname, values, varname, errcode)
  ! read attribute 'attname' return in 'values'.  If optional
  ! argument 'varname' is given, a variable attribute is returned.
  ! if the attribute is a 1d array, values should be an allocatable 1d
  ! array of the correct type.

  !subroutine write_attribute(dset, attname, values, varname, errcode)
  ! write attribute 'attname' with data in 'values'.  If optional
  ! argument 'varname' is given, a variable attribute is written.
  ! values can be a real(4), real(8), integer, string or 1d array.

  subroutine read_vardata_1d_r4(dset, varname, values, nslice, errcode)
    real(4), allocatable, dimension(:), intent(inout) :: values
    include "read_vardata_code_1d.f90"
  end subroutine read_vardata_1d_r4

  subroutine read_vardata_2d_r4(dset, varname, values, nslice, errcode)
    real(4), allocatable, dimension(:,:), intent(inout) :: values
    include "read_vardata_code_2d.f90"
  end subroutine read_vardata_2d_r4

  subroutine read_vardata_3d_r4(dset, varname, values, nslice, errcode)
    real(4), allocatable, dimension(:,:,:), intent(inout) :: values
    include "read_vardata_code_3d.f90"
  end subroutine read_vardata_3d_r4

  subroutine read_vardata_4d_r4(dset, varname, values, nslice, errcode)
    real(4), allocatable, dimension(:,:,:,:), intent(inout) :: values
    include "read_vardata_code_4d.f90"
  end subroutine read_vardata_4d_r4

  subroutine read_vardata_5d_r4(dset, varname, values, errcode)
    real(4), allocatable, dimension(:,:,:,:,:), intent(inout) :: values
    include "read_vardata_code_5d.f90"
  end subroutine read_vardata_5d_r4

  subroutine read_vardata_1d_r8(dset, varname, values, nslice, errcode)
    real(8), allocatable, dimension(:), intent(inout) :: values
    include "read_vardata_code_1d.f90"
  end subroutine read_vardata_1d_r8

  subroutine read_vardata_2d_r8(dset, varname, values, nslice, errcode)
    real(8), allocatable, dimension(:,:), intent(inout) :: values
    include "read_vardata_code_2d.f90"
  end subroutine read_vardata_2d_r8

  subroutine read_vardata_3d_r8(dset, varname, values, nslice, errcode)
    real(8), allocatable, dimension(:,:,:), intent(inout) :: values
    include "read_vardata_code_3d.f90"
  end subroutine read_vardata_3d_r8

  subroutine read_vardata_4d_r8(dset, varname, values, nslice, errcode)
    real(8), allocatable, dimension(:,:,:,:), intent(inout) :: values
    include "read_vardata_code_4d.f90"
  end subroutine read_vardata_4d_r8

  subroutine read_vardata_5d_r8(dset, varname, values, errcode)
    real(8), allocatable, dimension(:,:,:,:,:), intent(inout) :: values
    include "read_vardata_code_5d.f90"
  end subroutine read_vardata_5d_r8

  subroutine read_vardata_1d_int(dset, varname, values, nslice, errcode)
    integer, allocatable, dimension(:), intent(inout) :: values
    include "read_vardata_code_1d.f90"
  end subroutine read_vardata_1d_int

  subroutine read_vardata_2d_int(dset, varname, values, nslice, errcode)
    integer, allocatable, dimension(:,:), intent(inout) :: values
    include "read_vardata_code_2d.f90"
  end subroutine read_vardata_2d_int

  subroutine read_vardata_3d_int(dset, varname, values, nslice, errcode)
    integer, allocatable, dimension(:,:,:), intent(inout) :: values
    include "read_vardata_code_3d.f90"
  end subroutine read_vardata_3d_int

  subroutine read_vardata_4d_int(dset, varname, values, nslice, errcode)
    integer, allocatable, dimension(:,:,:,:), intent(inout) :: values
    include "read_vardata_code_4d.f90"
  end subroutine read_vardata_4d_int

  subroutine read_vardata_5d_int(dset, varname, values, errcode)
    integer, allocatable, dimension(:,:,:,:,:), intent(inout) :: values
    include "read_vardata_code_5d.f90"
  end subroutine read_vardata_5d_int

  subroutine write_vardata_1d_r4(dset, varname, values, nslice, errcode)
    real(4),  dimension(:), intent(in) :: values
    include "write_vardata_code.f90"
  end subroutine write_vardata_1d_r4

  subroutine write_vardata_2d_r4(dset, varname, values, nslice, errcode)
    real(4),  dimension(:,:), intent(in) :: values
    include "write_vardata_code.f90"
  end subroutine write_vardata_2d_r4

  subroutine write_vardata_3d_r4(dset, varname, values, nslice, errcode)
    real(4),  dimension(:,:,:), intent(in) :: values
    include "write_vardata_code.f90"
  end subroutine write_vardata_3d_r4

  subroutine write_vardata_4d_r4(dset, varname, values, nslice, errcode)
    real(4),  dimension(:,:,:,:), intent(in) :: values
    include "write_vardata_code.f90"
  end subroutine write_vardata_4d_r4

  subroutine write_vardata_5d_r4(dset, varname, values, nslice, errcode)
    real(4),  dimension(:,:,:,:,:), intent(in) :: values
    include "write_vardata_code.f90"
  end subroutine write_vardata_5d_r4

  subroutine write_vardata_1d_r8(dset, varname, values, nslice, errcode)
    real(8),  dimension(:), intent(in) :: values
    include "write_vardata_code.f90"
  end subroutine write_vardata_1d_r8

  subroutine write_vardata_2d_r8(dset, varname, values, nslice, errcode)
    real(8),  dimension(:,:), intent(in) :: values
    include "write_vardata_code.f90"
  end subroutine write_vardata_2d_r8

  subroutine write_vardata_3d_r8(dset, varname, values, nslice, errcode)
    real(8),  dimension(:,:,:), intent(in) :: values
    include "write_vardata_code.f90"
  end subroutine write_vardata_3d_r8

  subroutine write_vardata_4d_r8(dset, varname, values, nslice, errcode)
    real(8),  dimension(:,:,:,:), intent(in) :: values
    include "write_vardata_code.f90"
  end subroutine write_vardata_4d_r8

  subroutine write_vardata_5d_r8(dset, varname, values, nslice, errcode)
    real(8),  dimension(:,:,:,:,:), intent(in) :: values
    include "write_vardata_code.f90"
  end subroutine write_vardata_5d_r8

  subroutine write_vardata_1d_int(dset, varname, values, nslice, errcode)
    integer,  dimension(:), intent(in) :: values
    include "write_vardata_code.f90"
  end subroutine write_vardata_1d_int

  subroutine write_vardata_2d_int(dset, varname, values, nslice, errcode)
    integer,  dimension(:,:), intent(in) :: values
    include "write_vardata_code.f90"
  end subroutine write_vardata_2d_int

  subroutine write_vardata_3d_int(dset, varname, values, nslice, errcode)
    integer,  dimension(:,:,:), intent(in) :: values
    include "write_vardata_code.f90"
  end subroutine write_vardata_3d_int

  subroutine write_vardata_4d_int(dset, varname, values, nslice, errcode)
    integer,  dimension(:,:,:,:), intent(in) :: values
    include "write_vardata_code.f90"
  end subroutine write_vardata_4d_int

  subroutine write_vardata_5d_int(dset, varname, values, nslice, errcode)
    integer,  dimension(:,:,:,:,:), intent(in) :: values
    include "write_vardata_code.f90"
  end subroutine write_vardata_5d_int

  subroutine read_attribute_int_scalar(dset, attname, values, varname, errcode)
    integer, intent(inout) :: values
    include "read_scalar_attribute_code.f90"
  end subroutine read_attribute_int_scalar

  subroutine read_attribute_r4_scalar(dset, attname, values, varname, errcode)
    real(4), intent(inout) :: values
    include "read_scalar_attribute_code.f90"
  end subroutine read_attribute_r4_scalar

  subroutine read_attribute_r8_scalar(dset, attname, values, varname, errcode)
    real(8), intent(inout) :: values
    include "read_scalar_attribute_code.f90"
  end subroutine read_attribute_r8_scalar

  subroutine read_attribute_r4_1d(dset, attname, values, varname, errcode)
    real(4), intent(inout), allocatable, dimension(:) :: values
    include "read_attribute_code.f90"
  end subroutine read_attribute_r4_1d

  subroutine read_attribute_r8_1d(dset, attname, values, varname, errcode)
    real(8), intent(inout), allocatable, dimension(:) :: values
    include "read_attribute_code.f90"
  end subroutine read_attribute_r8_1d

  subroutine read_attribute_int_1d(dset, attname, values, varname, errcode)
    integer, intent(inout), allocatable, dimension(:) :: values
    include "read_attribute_code.f90"
  end subroutine read_attribute_int_1d

  subroutine read_attribute_char(dset, attname, values, varname, errcode)
    character(len=*), intent(inout) :: values
    include "read_scalar_attribute_code.f90"
  end subroutine read_attribute_char

  subroutine write_attribute_int_scalar(dset, attname, values, varname, errcode)
    integer, intent(in) :: values
    include "write_attribute_code.f90"
  end subroutine write_attribute_int_scalar

  subroutine write_attribute_r4_scalar(dset, attname, values, varname, errcode)
    real(4), intent(in) :: values
    include "write_attribute_code.f90"
  end subroutine write_attribute_r4_scalar

  subroutine write_attribute_r8_scalar(dset, attname, values, varname, errcode)
    real(8), intent(in) :: values
    include "write_attribute_code.f90"
  end subroutine write_attribute_r8_scalar

  subroutine write_attribute_r4_1d(dset, attname, values, varname, errcode)
    real(4), intent(in), allocatable, dimension(:) :: values
    include "write_attribute_code.f90"
  end subroutine write_attribute_r4_1d

  subroutine write_attribute_r8_1d(dset, attname, values, varname, errcode)
    real(8), intent(in), allocatable, dimension(:) :: values
    include "write_attribute_code.f90"
  end subroutine write_attribute_r8_1d

  subroutine write_attribute_int_1d(dset, attname, values, varname, errcode)
    integer, intent(in), allocatable, dimension(:) :: values
    include "write_attribute_code.f90"
  end subroutine write_attribute_int_1d

  subroutine write_attribute_char(dset, attname, values, varname, errcode)
    character(len=*), intent(in) :: values
    include "write_attribute_code.f90"
  end subroutine write_attribute_char

  elemental real function quantized(dataIn, nbits, dataMin, dataMax)
    implicit none
    integer, intent(in) :: nbits
    real(4), intent(in) :: dataIn, dataMin, dataMax
    real(4) offset, scale_fact
    ! convert data to 32 bit integers in range 0 to 2**nbits-1, then cast
    ! cast back to 32 bit floats (data is then quantized in steps
    ! proportional to 2**nbits so last 32-nbits in floating
    ! point representation should be zero for efficient zlib compression).
    scale_fact = (dataMax - dataMin) / (2**nbits-1); offset = dataMin
    quantized = scale_fact*(nint((dataIn - offset) / scale_fact)) + offset
  end function quantized

  function get_idate_from_time_units(dset) result(idate)
      ! return integer array with year,month,day,hour,minute,second
      ! parsed from time units attribute.
      type(Dataset), intent(in) :: dset
      integer idate(6)
      character(len=nf90_max_name) :: time_units
      integer ipos1,ipos2
      call read_attribute(dset, 'units', time_units, 'time')
      ipos1 = scan(time_units,"since",back=.true.)+1
      ipos2 = scan(time_units,"-",back=.false.)-1
      read(time_units(ipos1:ipos2),*) idate(1)
      ipos1 = ipos2+2; ipos2=ipos1+1
      read(time_units(ipos1:ipos2),*) idate(2)
      ipos1 = ipos2+2; ipos2=ipos1+1
      read(time_units(ipos1:ipos2),*) idate(3)
      ipos1 = scan(time_units,":")-2
      ipos2 = ipos1+1
      read(time_units(ipos1:ipos2),*) idate(4)
      ipos1 = ipos2+2
      ipos2 = ipos1+1
      read(time_units(ipos1:ipos2),*) idate(5)
      ipos1 = ipos2+2
      ipos2 = ipos1+1
      read(time_units(ipos1:ipos2),*) idate(6)
  end function get_idate_from_time_units
  
  function get_time_units_from_idate(idate, time_measure) result(time_units)
      ! create time units attribute of form 'hours since YYYY-MM-DD HH:MM:SS'
      ! from integer array with year,month,day,hour,minute,second
      ! optional argument 'time_measure' can be used to change 'hours' to
      ! 'days', 'minutes', 'seconds' etc.
      character(len=*), intent(in), optional :: time_measure
      integer, intent(in) ::  idate(6)
      character(len=12) :: timechar
      character(len=nf90_max_name) :: time_units
      if (present(time_measure)) then
         timechar = trim(time_measure)
      else
         timechar = 'hours'
      endif
      write(time_units,101) idate
101   format(' since ',i4.4,'-',i2.2,'-',i2.2,' ',&
      i2.2,':',i2.2,':',i2.2)
      time_units = trim(adjustl(timechar))//time_units
  end function get_time_units_from_idate

end module module_fv3gfs_ncio
