use strict;
use warnings;
use 5.010;

package RTx::REST;

our $VERSION = '0.01';

use UNIVERSAL::require;
use Plack::Builder;
use Web::Machine;
use Module::Pluggable
    sub_name    => "_resources",
    search_path => ["RTx::REST::Resource"],
    max_depth   => 4,
    require     => 1;

=encoding utf-8

=head1 NAME

RTx-REST - Adds a modern REST API to RT under /REST/2.0/

=head1 USAGE

Currently provided endpoints under C</REST/2.0/> are:

    GET /ticket/:id
    PUT /ticket/:id <JSON body>
    DELETE /ticket/:id
        Sets ticket status to "deleted".

    GET /queue/:id
    PUT /queue/:id <JSON body>
    DELETE /queue/:id
        Disables the queue.

    GET /user/:id
    PUT /user/:id <JSON body>
    DELETE /user/:id
        Disables the user.

For queues and users, C<:id> may be the numeric id or the unique name.

When a GET request is made, each endpoint returns a JSON representation of the
specified record, or a 404 if not found.

When a PUT request is made, the request body should be a modified copy (or
partial copy) of the JSON representation of the specified record, and the
record will be updated.

A DELETE request to a resource will delete or disable the underlying record.

=head2 Authentication

Currently authentication is limited to internal RT usernames and passwords,
provided via HTTP Basic auth.  Most HTTP libraries already have a way of
providing basic auth credentials when making requests.  Using curl, for
example:

    curl -u username:password …

This sort of authentication should B<always> be done over HTTPS/SSL for
security.  You should only serve up the C</REST/2.0/> endpoint over SSL.

=cut

# XXX TODO: API doc

sub resources {
    state @resources;
    @resources = grep { s/^RTx::REST::Resource:://; $_ } $_[0]->_resources
        unless @resources;
    return @resources;
}

sub resource {
    Web::Machine->new(
        resource => "RTx::REST::Resource::$_[0]",
    )->to_app;
}

sub app {
    my $class = shift;
    return sub {
        # XXX TODO: logging of SQL queries in RT's framework for doing so
        # XXX TODO: Need a dispatcher?  Or do it inside resources?  Web::Simple?
        RT::ConnectToDatabase();
        my $dispatch = builder {
            # XXX TODO: better auth integration
            enable "Auth::Basic",
                realm         => RT->Config->Get("rtname") . " API",
                authenticator => sub {
                    my ($user, $pass, $env) = @_;
                    my $cu = RT::CurrentUser->new;
                    $cu->Load($user);

                    if ($cu->id and $cu->IsPassword($pass)) {
                        $env->{"rt.current_user"} = $cu;
                        return 1;
                    } else {
                        RT->Logger->error("FAILED LOGIN for $user from $env->{REMOTE_ADDR}");
                        return 0;
                    }
                };
            mount "/\L$_"   => resource($_)
                for $class->resources;
            mount "/"       => sub { [ 404, ['Content-type' => 'text/plain'], ['Unknown resource'] ] };
        };
        $dispatch->(@_);
    }
}

# Called by RT::Interface::Web::Handler->PSGIApp
sub PSGIWrap {
    my ($class, $app) = @_;
    builder {
        mount "/REST/2.0"   => $class->app;
        mount "/"           => $app;
    };
}

=head1 INSTALLATION 

=over

=item C<perl Makefile.PL>

=item C<make>

=item C<make install>

May need root permissions

=item Edit your F</opt/rt4/etc/RT_SiteConfig.pm>

Add this line:

    Set(@Plugins, qw(RTx::REST));

or add C<RTx::REST> to your existing C<@Plugins> line.

=item Clear your mason cache

    rm -rf /opt/rt4/var/mason_data/obj

=item Restart your webserver

=back

=head1 AUTHOR

Thomas Sibley <trs@bestpractical.com>

=head1 BUGS

All bugs should be reported via email to
L<bug-RTx-REST@rt.cpan.org|mailto:bug-RTx-REST@rt.cpan.org>
or via the web at
L<rt.cpan.org|http://rt.cpan.org/Public/Dist/Display.html?Name=RTx-REST>.

=head1 LICENSE AND COPYRIGHT

This software is Copyright (c) 2013 by Best Practical Solutions

This is free software, licensed under:

  The GNU General Public License, Version 2, June 1991

=cut

1;
