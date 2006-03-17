package File::Find::Object::TreeCreate;

use strict;
use warnings;

use File::Spec;

sub new
{
    my $class = shift;
    my $self = {};
    bless $self, $class;
    $self->_initialize(@_);
    return $self;
}

sub _initialize
{
}

sub get_path
{
    my $self = shift;
    my $path = shift;

    my @components;

    if ($path =~ s{^./}{})
    {
        push @components, File::Spec->curdir();
    }
    
    my $is_dir = ($path =~ s{/$}{});
    push @components, split(/\//, $path);
    if ($is_dir)
    {
        return File::Spec->catdir(@components);
    }
    else
    {
        return File::Spec->catfile(@components);
    }
}

sub exist
{
    my $self = shift;
    return (-e $self->get_path(@_));
}

sub is_file
{
    my $self = shift;
    return (-f $self->get_path(@_));
}

sub is_dir
{
    my $self = shift;
    return (-d $self->get_path(@_));
}

sub contains 
{
    my ($self, $path, $expected) = @_;
    open my $in, "<", $self->get_path($path) or
        return 0;
    my $data;
    {
        local $/;
        $data = <$in>;
    }
    close($in);
    return ($data eq $expected);
}

1;

