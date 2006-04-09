# Stopwatch.pm Copyright Stewart Loving-Gibbard (sloving-gibbard@uswest.net) March 2003
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# This is a simple module to provide a stopwatch that can be started, stopped, and
# reset. 

use strict;

# If I'm not supposed to go into the Time:: namespace without clearance,
# someone please tell me!

package Time::Stopwatch;

# I really don't understand OO Perl very well - actually, the
# whole idea makes me queasy - so if you see obvious problems,
# please tell me & feel free to fix.

# Stewart Loving-Gibbard
# sloving-gibbard@uswest.net

use Time::HiRes;

sub new()
{
   my $invocant = shift;
   my $self = bless({}, ref $invocant || $invocant);
   $self->clear();
   return $self;
}

# Clear the stopwatch
sub clear()
{
   my $self = shift;
   # The time-of-day the stopwatch last started running. 0 if not currently running.
   $self->{startTimeOfDay} = 0;
   # Time in seconds elapsed before the stopwatch was last stopped. 0 if never stopped,
   # and after reset.
   $self->{timeElapsedBeforeLastStop} = 0;
   # Is the stopwatch presently running? 
   $self->{isRunning} = "false";
}

# Start the stopwatch running
sub start()
{
   my $self = shift;

   # Only does something if it is not yet running
   if ($self->{isRunning} eq "false")
   {
      # Mark the current time.
      $self->{startTimeOfDay} = [Time::HiRes::gettimeofday()];  
        
      # Throw flag
      $self->{isRunning} = "true";
   }
}


# Stop the stopwatch running. Elapsed time will halt here, but
# if started again, it will continue to accumulate.
sub stop()
{
   my $self = shift;

   # Only does something if it is already running
   if ($self->{isRunning} eq "true")
   {
      # Get the elapsed time for the latest start->stop interval
      my $elapsedTimeThisStartStopInterval = Time::HiRes::tv_interval( $self->{startTimeOfDay} );

      # Add this interval to any time already elapsed
      $self->{timeElapsedBeforeLastStop} = $self->{timeElapsedBeforeLastStop} + $elapsedTimeThisStartStopInterval;

      # Clear start time
      $self->{startTimeOfDay} = 0;

      # Stop it running
      $self->{isRunning} = "false";
   }
}


# Get the elapsed time on the stopwatch
sub getElapsedTime()
{
   my $self = shift;

   my $totalElapsedTime = 0;

   # If it is already running..
   if ($self->{isRunning} eq "true")
   {
      # Get the elapsed time for the latest start->stop interval
      my $elapsedTimeThisStartStopInterval = Time::HiRes::tv_interval( $self->{startTimeOfDay} );

      # Add this interval to any time already elapsed
      $totalElapsedTime = $self->{timeElapsedBeforeLastStop} + $elapsedTimeThisStartStopInterval;
   }
   elsif ($self->{isRunning} eq "false")
   {
      $totalElapsedTime = $self->{timeElapsedBeforeLastStop} 
   }
   else
   {
      # Error of some kind
   }

   return $totalElapsedTime;
}

# Packages must return true
1;

