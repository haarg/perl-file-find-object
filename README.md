File::Find::Object is an object-oriented and iterative replacement for
File::Find. I.e: it is a module for traversing a directory tree, and finding
all the files contained within it programatically.

# INSTALLATION

To install this module type the following:

    perl Makefile.PL
    make
    make test
    make install

after you install all of its dependencies.

Alternatively use the CPAN.pm module:

    # perl -MCPAN -e 'install File::Find::Object'

Or the newer CPANPLUS.pm module

    # perl -MCPANPLUS -e 'install File::Find::Object'

# DEPENDENCIES

This module's dependencies are:

1. A Perl version that supports the "use warnings" pragma.

2. The Class::XSAccessor module from CPAN.

# COPYRIGHT AND LICENSE

Copyright (C) 2005, 2006 by Olivier Thauvin

This package is free software; you can redistribute it and/or modify it under
the following terms:

1. The GNU General Public License Version 2.0 -
http://www.opensource.org/licenses/gpl-license.php

2. The Artistic License Version 2.0 -
http://www.perlfoundation.org/legal/licenses/artistic-2_0.html

3. At your option - any later version of either or both of these licenses.
