/***************************************************************************
 *   Copyright (C) 2010 Graziano Giuliani                                  *
 *   graziano.giuliani at aquila.infn.it                                   *
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 *   This program is distributed in the hope that it will be useful,       *
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of        *
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         *
 *   GNU General Public License for more details. (see COPYING)            *
 *                                                                         *
 *   You should have received a copy of the GNU General Public License     *
 *   along with this program; if not, write to the                         *
 *   Free Software Foundation, Inc.,                                       *
 *   59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.             *
 *                                                                         *
 *   LIC: GPL                                                              *
 *                                                                         *
 ***************************************************************************/

#include <iostream>

#include <netcdf.hh>

#include <cstring>
#include <cstdio>
#include <ctime>
#include <cstdlib>
#include <libgen.h>
#include <unistd.h>
#include <getopt.h>

#include <rcmio.h>
#include <rcmNc.h>
#include <gradsctl.h>

using namespace rcm;

static void help(char *pname);
static const char version[] = SVN_REV;

void help(char *pname)
{
  std::cerr << std::endl
      << "                 RegCM V4 ICTP NetCDF Postprocessor." << std::endl
      << std::endl
      << "This simple program converts binary ICBC files from RegCM V4 "
      << "into NetCDF" << std::endl << "CF-1.4 convention compliant data files."
      << std::endl << std::endl << "I need ONE mandatory argument:"
      << std::endl << std::endl
      << "    regcm.in       - path to regcm.in of RegCM model v4" << std::endl
      << std::endl << "Example:" << std::endl << std::endl << "     " << pname
      << " [options] regcm.in"
      << std::endl << std::endl
      << "where options can be in:" << std::endl << std::endl
  << "   --sequential              : Set I/O non direct (direct access default)"
      << std::endl
  << "   --little_endian           : Set I/O endianess to LITTLE (BIG default)"
      << std::endl
  << "   --help/-h                 : Print this help"
      << std::endl
  << "   --version/-V              : Print versioning information"
      << std::endl << std::endl;
   return;
}

int main(int argc, char *argv[])
{
  bool ldirect, lbigend;
  int iseq, ilittle;
  ldirect = true;
  lbigend = true;
  iseq = 0;
  ilittle = 0;

  char *pname = basename(argv[0]);
  while (1)
  {
    static struct option long_options[] = {
      { "sequential", no_argument, &iseq, 1},
      { "little_endian", no_argument, &ilittle, 1},
      { "help", no_argument, 0, 'h'},
      { "version", no_argument, 0, 'V'},
      { 0, 0, 0, 0 }
    };
    int optind, c = 0;
    c = getopt_long (argc, argv, "hV",
                     long_options, &optind);
    if (c == -1) break;
    switch (c)
    {
      case 0:
        if (long_options[optind].flag != 0) break;
      case 'h':
        help(pname);
        return 0;
        break;
      case 'V':
        std::cerr << "This is " << pname << " version " << version
                  << std::endl;
        return 0;
      case '?':
        break;
      default:
        std::cerr << "Unknown switch '" << (char) c << "' discarded."
                  << std::endl;
        break;
    }
  }

  if (argc - optind != 1)
  {
    std::cerr << std::endl << "Howdy there, wrong number of arguments."
              << std::endl;
    help(pname);
    return -1;
  }

  if (iseq == 1) ldirect = false;
  if (ilittle == 1) lbigend = false;

  try
  {
    char *regcmin = strdup(argv[optind++]);
 
    rcminp inpf(regcmin);
    domain_data d(inpf);
    char *datadir = strdup(inpf.valuec("dirglob"));
    rcmio rcmout(datadir, lbigend, ldirect);

    char *experiment = strdup(inpf.valuec("domname"));
    char dominfo[PATH_MAX];

    sprintf(dominfo, "%s%s%s.INFO", inpf.valuec("dirter"),
            separator, experiment);
    std::cout << "Opening " << dominfo << std::endl;
    rcmout.read_domain(dominfo, d);

    bcdata b(d, inpf);

    char fname[PATH_MAX];
    char ctlname[PATH_MAX];
    sprintf(fname, "ICBC_%s.nc", experiment);
    sprintf(ctlname, "ICBC_%s.ctl", experiment);
    gradsctl ctl(ctlname, fname);
    bcNc bcnc(fname, experiment, d, ctl);

    std::cout << "Processing ICBC";
    while ((rcmout.bc_read_tstep(b)) == 0)
    {
      std::cout << ".";
      std::cout.flush();
      bcnc.put_rec(b, ctl);
    }
    std::cout << " Done." << std::endl;

    ctl.finalize( );
    free(datadir);
    free(experiment);
  }
  catch (const char *e)
  {
    std::cerr << "Error : " << e << std::endl;
    return -1;
  }
  catch (...)
  {
    return -1;
  }

  std::cout << "Successfully completed processing." << std::endl;
  return 0;
}
