# ======================================================================
#
# Copyright (C) 2000-2003 Paul Kulchenko (paulclinger@yahoo.com)
# SOAP::Lite is free software; you can redistribute it
# and/or modify it under the same terms as Perl itself.
#
# $Id: Trace.pm,v 1.1 2004/10/12 18:47:55 byrnereese Exp $
#
# ======================================================================

=pod

=head1 NAME

SOAP::Trace - used only to manage and manipulate the runtime tracing of execution within the toolkit

=head1 DESCRIPTION

This class has no methods or objects. It is used only to manage and manipulate the runtime tracing of execution within the toolkit. In absence of methods, this section reviews the events that may be configured and the ways of configuring them. 

=head1 SYNOPSIS

Tracing is enabled by the SOAP::Lite import method. This is usually done at compile-time, though it may be done explicitly by calling import directly. The commands for setting up tracing start with the keyword +trace. Alternately, +debug may be used; the two are interchangeable. After the initial keyword, one or more of the signals detailed here may be specified, optionally with a callback to handle them. When specifying multiple signals to be handled by a single callback, it is sufficient to list all of them first, followed finally by the callback, as in: 

   use SOAP::Lite +trace => 
     method => fault => \&message_level, 
     trace => objects => \&lower_level; 

In the fragment, the reference to message_level is installed as the callback for both method and fault signals, while lower_level is installed for trace and object events. If callbacks aren't explicitly provided, the default tracing action is to log a message to Perl's STDOUT file descriptor. Callbacks should expect a one or more arguments passed in, though the nature of the arguments varies based on the signal. 

Any signal can be disabled by prefacing the name with a hyphen, such as -result. This is useful with the pseudosignal "all," which is shorthand for the full list of signals. The following fragment disables only the two signals, while still enabling the rest: 

    SOAP::Lite->import(+trace => all => -result => -parameters);

If the keyword +trace (or +debug) is used without any signals specified, it enables all signals (as if all were implied). 

The signals and their meaning follow. Each also bears a note as to whether the signal is relevant to a server application, client application, or both. 

=head1 TRACE SIGNALS

=over

=item transport I<Client only>

Triggered in the transport layer just before a request is sent and immediately after a response is received. Each time the signal is sent, the sole argument to the callback is the relevant object. On requests, this is a L<HTTP::Request> object; for responses, it's a L<HTTP::Response> object.

=item dispatch I<Server only>

Triggered with the full name of the method being dispatched, just before execution is passed to it. It is currently disabled in SOAP::Lite 0.55.

=item result I<Server only>

Triggered after the method has been dispatched and is passed the results returned from the method as a list. The result values have not yet been serialized when this signal is sent.

=item parameters I<Server only>

Triggered before a method call is actually dispatched, with the data that is intended for the call itself. The parameters for the method call are passed in as a list, after having been deserialized into Perl data.

=item headers I<Server only>

This signal should be for triggering on the headers of an incoming message, but it isn't implemented as of SOAP::Lite 0.55.

=item objects I<Client or server>

Highlights when an object is instantiated or destroyed. It is triggered in the new and DESTROY methods of the various SOAP::Lite classes.

=item method I<Client or server>

Triggered with the list of arguments whenever the envelope method of L<SOAP::Serializer> is invoked with an initial argument of method. The initial string itself isn't passed to the callback.

=item fault I<Client or server>

As with the method signal earlier, except that this signal is triggered when SOAP::Serializer::envelope is called with an initial argument of fault.

=item freeform I<Client or server>

Like the two previous, this signal is triggered when the method SOAP::Serializer::envelope is called with an initial parameter of freeform. This syntax is used when the method is creating SOAP::Data objects from free-form input data.

=item trace I<Client or server>

Triggered at the entry-point of many of the more-significant functions. Not all the functions within the SOAP::Lite classes trigger this signal. Those that do are primarily the highly visible functions described in the interface descriptions for the various classes.

=item debug I<Client or server>

Used in the various transport modules to track the contents of requests and responses (as ordinary strings, not as objects) at different points along the way.

=back

=head1 EXAMPLES

=head2 SELECTING SIGNALS TO TRACE

The following code snippet will enable tracing for all signals:

  use SOAP::Lite +trace => 'all';

Or, the following will also do the trick:

  use SOAP::Lite +trace;

You can disable tracing for a set of signals by prefixing the signal name with a hyphen. Therefore, if you wish to enable tracing for every signal EXCEPT transport signals, then you would use the code below:

  use SOAP::Lite +trace => [ qw(all -transport) ];

=head2 LOGGING SIGNALS TO A FILE

You can optionally provide a subroutine or callback to each signal trace you declare. Each time a signal is received, it is passed to the corresponding subroutine. For example, the following code effectively logs all fault signals to a file called fault.log:

  use SOAP::Lite +trace => [ fault => \&log_faults ];

  sub log_faults {
    open LOGFILE,">fault.log";
    print LOGFILE, $_[0] . "\n";
    close LOGFILE;
  }

You can also use a single callback for multiple signals using the code below:

  use SOAP::Lite +trace => [ method, fault => \&log ];

=head2 LOGGING MESSAGE CONTENTS

The transport signal is unique in the that the signal is not a text string, but the actually HTTP::Request being sent (just prior to be sent), or HTTP::Response object (immediately after it was received). The following code sample shows how to make use of this:

  use SOAP::Lite +trace => [ transport => &log_message ];

  sub log_message {
    my ($in) = @_;
    if (class($in) eq "HTTP::Request") {
      # do something...
      print $in->contents; # ...for example
    } elsif (class($in) eq "HTTP::Response") {
      # do something
    }
  }

=head2 ON_DEBUG

The C<on_debug> method is available, as in:

  use SOAP::Lite;
  my $client = SOAP::Lite
    ->uri($NS)
    ->proxy($HOST)
    ->on_debug( sub { print @_; } );

=head1 ACKNOWLEDGEMENTS

Special thanks to O'Reilly publishing which has graciously allowed SOAP::Lite to republish and redistribute large excerpts from I<Programming Web Services with Perl>, mainly the SOAP::Lite reference found in Appendix B.

=head1 COPYRIGHT

Copyright (C) 2000-2004 Paul Kulchenko. All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHORS

Paul Kulchenko (paulclinger@yahoo.com)

Randy J. Ray (rjray@blackperl.com)

Byrne Reese (byrne@majordojo.com)

=cut
