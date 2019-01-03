package Taskwarrior::Kusarigama::Task;
# ABSTRACT: per-task Taskwarrior::Kusarigama::Wrapper

use strict;

use experimental 'postderef';

use Clone;

=head1 SYNOPSIS

    use Taskwarrior::Kusarigama::Wrapper;
    use Taskwarrior::Kusarigama::Task;

    my $tw = Taskwarrior::Kusarigama::Wrapper->new;

    my ( $task ) = $tw->export;

    say $task->info;

=head1 DESCRIPTION

Thin wrapper around the task hashrefs that calls L<Taskwarrior::Kusarigama::Wrapper>.

Unless specified otherwise, the task must have
an C<uuid> to be acted upon.

=head1 METHODS

=head2 new

    my $task = Taskwarrior::Kusarigama::Task->new( \%data );

    my $task = Taskwarrior::Kusarigama::Task->new( $wrapper, \%data );

Constructor. Takes in a raw hashref of the task's
attributes as would be give by C<task export>, and
an optional C<$wrapper>, which is the
L<Taskwarrior::Kusarigama::Wrapper>
object to use. The wrapper object can also
be passed via a C<_wrapper> attribute.

    # equivalent to the two-argument 'new'
    my $task = Taskwarrior::Kusarigama::Task->new(
        { _wrapper => $wrapper, %data }
    );


=cut

sub new {
    my $class = shift;
    $class = ref $class if ref $class;

    my $data = pop;

    $data->{_wrapper} = shift if @_;

    bless $data, $class;
}

sub add_note {
    my ( $self, $note ) = @_;

    $self->{annotations} ||= [];

    require DateTime::Functions;
    my $now = DateTime::Functions::now();

    my $timestamp = $now->ymd("") . 'T' . $now->hms("") . "Z";

    push $self->{annotations}->@*, {
        entry => $timestamp,
        description => $note,
    };
}

=head2 clone

Clone the current task. All attributes are copied, except for
C<id>, C<uuid>, C<urgency>, C<status>, C<entry> and C<modified>.

=cut

sub clone {
    my $self = shift;

    my $cloned = Clone::clone($self);

    delete $cloned->{$_} for qw/ id uuid entry modified end urgency status /;

    return $self->new( $self->{_wrapper}, $cloned );
}

sub data {
    my $self = shift;
    require List::Util;
    return { List::Util::pairgrep( sub { $a !~ /^_/ }, %$self ) }
}

sub save {
    my $self = shift;

    my $new = $self->{_wrapper}->save($self->data);

    %$self = %$new;
    # delete $self->{$_} for keys %$self;
    # $self->{$_} = $new->{$_} for keys %$new;

    return  $self;
}


sub AUTOLOAD {
    my $self = shift;

    (my $meth = our $AUTOLOAD) =~ s/.+:://;
    return if $meth eq 'DESTROY';

    $meth =~ tr/_/-/;

    $self->{_wrapper} ||= Taskwarrior::Kusarigama::Wrapper->new;

    unshift @_, [] unless 'ARRAY' eq ref $_[0];

    use Carp;
    my $uuid = $self->{uuid}
        or croak "task doesn't have an uuid\n";

    push $_[0]->@*, { uuid => $uuid };

    return $self->{_wrapper}->RUN($meth, @_);
}


1;

__END__
