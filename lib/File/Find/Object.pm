package File::Find::Object::DeepPath;

use strict;
use warnings;

use integer;

use base 'File::Find::Object::PathComp';

use File::Spec;

sub new {
    my ($class, $top, $from) = @_;

    my $self = {};
    bless $self, $class;

    $self->_dir([ @{$top->_curr_comps()} ]);
    $self->_stat_ret($top->_top_stat_copy());

    my $find = { %{$from->_inodes()} };
    if (my $inode = $self->_inode) {
        $find->{join(",", $self->_dev(), $inode)} =
            scalar(@{$top->_dir_stack()});
    }
    $self->_set_inodes($find);

    $self->_last_dir_scanned(undef);

    $from->_dir($self->_dir_copy());

    $top->_fill_actions($self);

    push @{$top->_curr_comps()}, "";

    return $top->_open_dir() ? $self : undef;
}

sub _move_next
{
    my ($self, $top) = @_;

    if (defined($self->_curr_file(
            $top->_current_father()->_next_traverse_to()
       )))
    {
        $top->_curr_comps()->[-1] = $self->_curr_file();
        $top->_calc_curr_path();

        $top->_fill_actions($self);
        $top->_mystat();

        return 1;
    }
    else {
        return 0;
    }
}

package File::Find::Object::TopPath;

use base 'File::Find::Object::PathComp';

sub new {
    my $class = shift;
    my $top = shift;

    my $self = {};
    bless $self, $class;

    $top->_fill_actions($self);

    return $self;
}


sub _move_to_next_target
{
    my $self = shift;
    my $top = shift;

    my $target = $self->_curr_file($top->_calc_next_target());
    @{$top->_curr_comps()} = ($target);
    $top->_calc_curr_path();

    return $target;
}

sub _move_next
{
    my $self = shift;
    my $top = shift;

    while ($top->_increment_target_index())
    {
        if (-e $self->_move_to_next_target($top))
        {
            $top->_fill_actions($self);
            $top->_mystat();
            $self->_stat_ret($top->_top_stat_copy());
            $top->_dev($self->_dev);

            my $inode = $self->_inode();
            $self->_set_inodes(
                ($inode == 0)
                ? {}
                :
                {
                    join(",", $self->_dev(), $inode) => 0,
                },
            );

            return 1;
        }
    }

    return 0;
}

package File::Find::Object;

use strict;
use warnings;

use base 'File::Find::Object::Base';

use File::Find::Object::Result;

use Fcntl ':mode';
use List::Util ();

sub _get_options_ids
{
    my $class = shift;
    return [qw(
        callback
        depth
        filter
        followlink
        nocrossfs
    )];
}

# _curr_comps are the components (comps) of the master object's current path.
# _curr_path is the concatenated path itself.

use Class::XSAccessor
    accessors => {
        (map { $_ => $_ } 
        (qw(
            _check_subdir_h
            _curr_comps
            _current
            _curr_path
            _def_actions
            _dev
            _dir_stack
            item_obj
            _target_index
            _targets
            _top_is_dir
            _top_is_link
            _top_stat
            ), 
            @{__PACKAGE__->_get_options_ids()}
        )
        )
    }
    ;

__PACKAGE__->_make_copy_methods([qw(
    _top_stat
    )]
);

use Carp;

our $VERSION = '0.1.9';

sub new {
    my ($class, $options, @targets) = @_;

    # The *existence* of an _st key inside the struct
    # indicates that the stack is full.
    # So now it's empty.
    my $tree = {
        _dir_stack => [],
        _curr_comps => [],
    };

    bless($tree, $class);

    foreach my $opt (@{$tree->_get_options_ids()})
    {
        $tree->$opt($options->{$opt});
    }

    $tree->_gen_check_subdir_helper();

    $tree->_targets(\@targets);
    $tree->_target_index(-1);

    $tree->_calc_default_actions();

    push @{$tree->_dir_stack()},
        $tree->_current(File::Find::Object::TopPath->new($tree))
        ;

    $tree->_last_dir_scanned(undef);

    return $tree;
}

sub _curr_not_a_dir {
    return !shift->_top_is_dir();
}

# Calculates _curr_path from $self->_curr_comps().
# Must be called whenever _curr_comps is modified.
sub _calc_curr_path
{
    my $self = shift;

    $self->_curr_path(File::Spec->catfile(@{$self->_curr_comps()}));

    return;
}

sub _calc_current_item_obj {
    my $self = shift;

    my @comps = @{$self->_curr_comps()};

    my $ret =
    {
        path => scalar($self->_curr_path()),
        dir_components => \@comps,
        base => shift(@comps),
        stat_ret => scalar($self->_top_stat_copy()),
    };

    if ($self->_curr_not_a_dir())
    {
        $ret->{basename} = pop(@comps);
    }

    return bless $ret, "File::Find::Object::Result";
}

sub next_obj {
    my $self = shift;

    until (     $self->_process_current 
            || ((!$self->_master_move_to_next())
               && $self->_me_die())
            )
    {
        # Do nothing
    }

    return $self->item_obj();
}

sub next {
    my $self = shift;

    $self->next_obj();

    return $self->item();
}

sub item {
    my $self = shift;

    return $self->item_obj() ? $self->item_obj()->path() : undef;
}

sub _current_father {
    return shift->_dir_stack->[-2];
}

sub _increment_target_index
{
    my $self = shift;
    $self->_target_index( $self->_target_index() + 1 );

    return ($self->_target_index() < scalar(@{$self->_targets()}));
}

sub _calc_next_target
{
    my $self = shift;

    my $target = $self->_targets()->[$self->_target_index()];

    return defined($target) ? File::Spec->canonpath($target) : undef;
}

sub _master_move_to_next {
    my $self = shift;

    return $self->_current()->_move_next($self);
}

sub _me_die {
    my $self = shift;

    if (exists($self->{_st})) {
        return $self->_become_default();
    }

    $self->item_obj(undef());
    return 1;
}

sub _become_default
{
    my $self = shift;

    my $st = $self->_dir_stack();

    pop(@$st);
    $self->_current($st->[-1]);
    pop(@{$self->_curr_comps()});

    if (@$st == 1)
    {
        delete($self->{_st});
    }
    else
    {
        # If depth is false, then we no longer need the _curr_path
        # of the directories above the previously-set value, because we 
        # already traversed them.
        if ($self->depth())
        {
            $self->_calc_curr_path();
        }
    }

    return 0;
}

sub _calc_default_actions {
    my $self = shift;

    my @calc_obj =
        $self->callback()
        ? (qw(_set_obj_skip _run_cb))
        : (qw(_set_obj))
        ;

    my @rec = qw(_recurse);

    $self->_def_actions(
        [$self->depth()
            ? (@rec, @calc_obj)
            : (@calc_obj, @rec)
        ]
    );

    return;
}

sub _fill_actions {
    my $self = shift;
    my $other = shift;

    $other->_actions([ @{$self->_def_actions()} ]);

    return;
}

sub _mystat {
    my $self = shift;

    $self->_top_stat([lstat($self->_curr_path())]);

    $self->_top_is_dir(scalar(-d _));

    if ($self->_top_is_link(scalar(-l _))) {
        stat($self->_curr_path());
        $self->_top_is_dir(scalar(-d _));
    }

    return "SKIP";
}

sub _next_action {
    my $self = shift;

    return shift(@{$self->_current->_actions()});
}

sub _check_process_current {
    my $self = shift;

    return (defined($self->_current->_curr_file()) && $self->_filter_wrapper());
}

# Return true if there is somthing next
sub _process_current {
    my $self = shift;

    if (!$self->_check_process_current())
    {
        return 0;
    }
    else
    {
        return $self->_process_current_actions();
    }
}

sub _set_obj {
    my $self = shift;

    $self->item_obj($self->_calc_current_item_obj());

    return 1;
}

sub _set_obj_skip {
    my $self = shift;

    $self->item_obj($self->_calc_current_item_obj());

    return "SKIP";
}

sub _run_cb {
    my $self = shift;

    $self->callback()->($self->_curr_path());

    return 1;
}

sub _process_current_actions
{
    my $self = shift;

    while (my $action = $self->_next_action())
    {
        my $status = $self->$action();

        if ($status ne "SKIP")
        {
            return $status;
        }
    }

    return 0;
}

sub _recurse
{
    my $self = shift;

    $self->_check_subdir() or 
        return "SKIP";

    push @{$self->_dir_stack()}, 
        $self->_current(
            File::Find::Object::DeepPath->new(
                $self,
                $self->_current()
            )
        );

    $self->{_st} = 1;

    return 0;
}

sub _filter_wrapper {
    my $self = shift;

    return defined($self->filter()) ?
        $self->filter()->($self->_curr_path()) :
        1;
}

sub _check_subdir 
{
    my $self = shift;

    # If current is not a directory always return 0, because we may
    # be asked to traverse single-files.

    if ($self->_curr_not_a_dir())
    {
        return 0;
    }
    else
    {
        return $self->_check_subdir_h()->($self);
    }
}



sub _warn_about_loop
{
    my $self = shift;
    my $ptr = shift;

    # Don't pass strings directly to the format.
    # Instead - use %s
    # This was a security problem.
    warn(
        sprintf(
            "Avoid loop %s => %s\n",
                $ptr->_dir_as_string(),
                $self->_curr_path()
        )
    );

    return;
}

sub _is_loop {
    my $self = shift;

    my $key = join(",", @{$self->_top_stat()}[0,1]);
    my $lookup = $self->_current->_inodes;

    if (exists($lookup->{$key})) {
        $self->_warn_about_loop($self->_dir_stack->[$lookup->{$key}]);
        return 1;
    }
    else {
        return;
    }
}

# We eval "" the helper of check_subdir because the conditions that
# affect the checks are instance-wide and constant and so we can
# determine how the code should look like.

sub _gen_check_subdir_helper {
    my $self = shift;

    my @clauses;

    if (!$self->followlink()) {
        push @clauses, '$s->_top_is_link()';
    }
    
    if ($self->nocrossfs()) {
        push @clauses, '($s->_top_stat->[0] != $s->_dev())';
    }

    push @clauses, '$s->_is_loop()';

    $self->_check_subdir_h(
        _context_less_eval(
          'sub { my $s = shift; ' 
        . 'return ((!exists($s->{_st})) || !('
        . join("||", @clauses) . '));'
        . '}'
        )
    );
}

sub _context_less_eval {
    my $code = shift;
    return eval $code;
}

sub _open_dir {
    my $self = shift;

    return $self->_current()->_component_open_dir();
}

sub set_traverse_to
{
    my ($self, $children) = @_;

    # Make sure we scan the current directory for sub-items first.
    $self->get_current_node_files_list();

    $self->_current->_traverse_to([@$children]);
}

sub get_traverse_to
{
    my $self = shift;

    return $self->_current->_traverse_to_copy();
}

sub get_current_node_files_list
{
    my $self = shift;

    $self->_current->_dir($self->_curr_comps());

    # _open_dir can return undef if $self->_current is not a directory.
    if ($self->_open_dir())
    {
        return $self->_current->_files_copy();
    }
    else
    {
        return [];
    }
}

sub prune
{
    my $self = shift;

    return $self->set_traverse_to([]);
}

1;

__END__

=head1 NAME

File::Find::Object - An object oriented File::Find replacement

=head1 SYNOPSIS

    use File::Find::Object;
    my $tree = File::Find::Object->new({}, @targets);

    while (my $r = $tree->next()) {
        print $r ."\n";
    }

=head1 DESCRIPTION

File::Find::Object does same job as File::Find but works like an object and 
with an iterator. As File::Find is not object oriented, one cannot perform
multiple searches in the same application. The second problem of File::Find 
is its file processing: after starting its main loop, one cannot easilly wait 
for another event and so get the next result.

With File::Find::Object you can get the next file by calling the next() 
function, but setting a callback is still possible.

=head1 FUNCTIONS

=head2 new

    my $ffo = File::Find::Object->new( { options }, @targets);

Create a new File::Find::Object object. C<@targets> is the list of 
directories or files which the object should explore.

=head3 options

=over 4

=item depth

Boolean - returns the directory content before the directory itself.

=item nocrossfs

Boolean - doesn't continue on filesystems different than the parent.

=item followlink

Boolean - follow symlinks when they point to a directory.

You can safely set this option to true as File::Find::Object does not follow 
the link if it detects a loop.

=item filter

Function reference - should point to a function returning TRUE or FALSE. This 
function is called with the filename to filter, if the function return FALSE, 
the file is skipped.

=item callback

Function reference - should point to a function, which would be called each 
time a new file is returned. The function is called with the current filename 
as an argument.

=back

=head2 next

Returns the next file found by the File::Find::Object. It returns undef once
the scan is completed.

=head2 item

Returns the current filename found by the File::Find::Object object, i.e: the
last value returned by next().

=head2 next_obj

Like next() only returns the result as a convenient 
L<File::Find::Object::Result> object. C<< $ff->next() >> is equivalent to
C<< $ff->next_obj()->path() >>.

=head2 item_obj

Like item() only returns the result as a convenient 
L<File::Find::Object::Result> object. C<< $ff->item() >> is equivalent to
C<< $ff->item_obj()->path() >>.

=head2 $ff->set_traverse_to([@children])

Sets the children to traverse to from the current node. Useful for pruning
items to traverse.

=head2 $ff->prune()

Prunes the current directory. Equivalent to $ff->set_traverse_to([]).

=head2 [@children] = $ff->get_traverse_to()

Retrieves the children that will be traversed to.

=head2 [@files] = $ff->get_current_node_files_list()

Gets all the files that appear in the current directory. This value is
constant for every node, and is useful to use as the basis of the argument
for C<set_traverse_to()>.

=head1 BUGS

No bugs are known, but it doesn't mean there aren't any.

=head1 SEE ALSO

There's an article about this module in the Perl Advent Calendar of 2006:
L<http://perladvent.pm.org/2006/2/>.

L<File::Find> is the core module for traversing files in perl, which has
several limitations.

L<File::Next>, L<File::Find::Iterator>, L<File::Walker> and the unmaintained
L<File::FTS> are alternatives to this module.

=head1 LICENSE

Copyright (C) 2005, 2006 by Olivier Thauvin

This package is free software; you can redistribute it and/or modify it under 
the following terms:

1. The GNU General Public License Version 2.0 - 
http://www.opensource.org/licenses/gpl-license.php

2. The Artistic License Version 2.0 -
http://www.perlfoundation.org/legal/licenses/artistic-2_0.html

3. At your option - any later version of either or both of these licenses.

=cut

