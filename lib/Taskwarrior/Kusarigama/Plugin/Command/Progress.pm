package Taskwarrior::Kusarigama::Plugin::Command::Progress;
# ABSTRACT: Record progress on a task

=head1 SYNOPSIS

    $ task add read ten books goal:10

    ... later on ...

    $ task 'read ten books' progress 

=head1 DESCRIPTION

Tasks get two new UDAs: C<goal>, which sets a
numeric goal to reach, and C<progress>, which is 
the current state of progress. 

Progress can be updated or asked via the C<progress> command.

    # add 3 units toward the goal
    $ task 123 progress 3

    # oops, two steps back
    $ task 123 progress -2

    # set progress to an absolute value
    $ task 123 progress =9

    # defaults to a +1 increment
    $ task 123 progress

    # record progress and add a note
    $ task 123 progress +3 I did a little bit of the thing

    # ask about current task progress
    $ task 123 progress ?

    # ask about current task progress on three step forward
    # real progress don't modified
    $ task 123 progress ?3

If the task has a due date, the progress command will
also show a short report of your actual rate of completion
version what is required to meet the goal on time.

    $ task 630 progress =170
    630 =======------------ 170/475 (35.8%)
    15 days left, you are ahead of schedule (170 vs 118)
    rate so far: 34/day, rate needed: 20/day

=cut    

use strict;
use warnings;

use 5.10.0;

use Moo;

extends 'Taskwarrior::Kusarigama::Plugin';

with 'Taskwarrior::Kusarigama::Hook::OnCommand',
      'Taskwarrior::Kusarigama::Hook::OnAdd',
      'Taskwarrior::Kusarigama::Hook::OnModify';

use experimental 'postderef';

has custom_uda => (
    is => 'ro',
    default => sub{ +{
        goal     => 'quantifiable goal',
        progress => "where we're at",
    }},
);

sub on_add {
    goto &on_modify;
}

sub on_modify {
    my( $self, $task ) = @_;

    no warnings 'uninitialized';

    my $goal = $task->{goal} or return;

    my $progress = $task->{progress};

    $task->{description} =~ s#\(\d+\/\d+\)(.*?)$#$1#;
    $task->{description} .= sprintf ' (%d/%d)', $progress, $goal;

    return $task;
}

sub formatted_rate {
    my ( $self, $rate ) = @_;

    my $unit;

    if( $rate > 1 ) {
        $unit = 'day';
    }
    elsif( $rate > 1/7 )  {
        $rate *= 7;
        $unit = 'week';
    }
    elsif( $rate > 1/30 )  {
        $rate *= 30;
        $unit = 'month';
    }
    else {
        $rate *= 365;
        $unit = 'year';
    }

    return sprintf "%d/%s", $rate, $unit;
}

sub on_command {
    my $self = shift;

    # only grab goal'ed tasks
    my @tasks = $self->run_task->export( $self->pre_command_args, { 'goal.any' => '' } );

    die "no tasks found\n" unless @tasks;

    my $note = $self->post_command_args =~ s/\s*(\??)(=?)(-?\d*)\s*//r;

    no warnings 'uninitialized';
    for my $task ( @tasks ) {
        my $save = !$1;

        my $progress = !$save ? $task->{progress} 
                     : $2     ? $3 
                     :          ($3||1) + $task->{progress};

        my $goal = $task->{goal};

        my $ratio = $progress / $goal;

        print $task->{id}, ' ', '=' x ( 20 * $ratio ), '-' x ( 20 * ( 1 - $ratio ) ), ' ', $progress, '/', $goal, sprintf(" (%.1f%%)\n", $ratio*100), "\n";

        my $id = $task->{uuid};
        $self->run_task->mod( [ $id ], { progress => $progress } ) if $save;
        $self->run_task->annotate( [ $id ], $note ) if $note and $save;
        if ( $progress >= $task->{goal} ) {
            say "goal achieved!";
            $self->run_task->done( [ $id ] ) if $save;
        }
        elsif( $task->{due} ) {
            my ( $span ) = $self->calc( $task->{due}, '-', $task->{entry} ) =~ /(\d+)D/;
            my ( $now )  = $self->calc( $task->{due}, '-', 'now' ) =~ /(\d+)D/g;
            my $should_be_at = eval { $task->{goal} * ($span-$now) / $span };
            if( $should_be_at ) {
                my $comp = ('on track', 'ahead', 'behind')[ $progress <=> $should_be_at ];

                printf "%d days left, you are %s of schedule (%d vs %d)\n",
                    $now, $comp, $progress, $should_be_at;

                my @stats;

                if( my $so_far = eval { $progress /  ($span-$now) } ) {
                    push @stats, sprintf "rate so far: %s", 
                        $self->formatted_rate($so_far);
                }

                if( my $needed = eval { ($task->{goal} - $progress) / $now } ) {
                    push @stats, sprintf "rate needed: %s", 
                        $self->formatted_rate($needed);
                }

                say join ', ', @stats if @stats;

            }
        }
    }

};

1;

