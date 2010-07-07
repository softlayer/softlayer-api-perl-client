# Copyright (c) 2010, SoftLayer Technologies, Inc. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#  * Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
#  * Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#  * Neither SoftLayer Technologies, Inc. nor the names of its contributors may
#    be used to endorse or promote products derived from this software without
#    specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

package SoftLayer::API::SOAP;

use 5.008008;
use strict;
use SOAP::Lite;
use XML::Hash::LX;

require Exporter;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration use SoftLayer::API::SOAP ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(

) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(

);

our $VERSION = '0.2';

# Your SoftLayer API username. You may overide this value when calling new().
my $API_USER = '';

# Your SoftLayer API user's authentication key. You may overide this value when
# calling new(). See <https://manage.softlayer.com/Administrative/apiKeychain>
# to maange your API keys.
my $API_KEY = '';

# The base URL of the SoftLayer SOAP API's WSDL files over the public Internet.
our $API_PUBLIC_ENDPOINT = 'https://api.softlayer.com/soap/v3/';

# The base URL of the SoftLayer SOAP API's WSDL files over SoftLayer's private
# network.
our $API_PRIVATE_ENDPOINT = 'http://api.service.softlayer.com/soap/v3/';

# The API endpoint base URL used by the client.
my $API_BASE_URL = $SoftLayer::API::SOAP::API_PUBLIC_ENDPOINT;

# Used in AUTOLOAD() for custom method handling.
our $AUTOLOAD;

# Create a SoftLayer API SOAP Client
#
# Retrieve a new SoftLayer::API::SOAP object for a specific SoftLayer API
# service using either the package's variables $API_USER and $API_KEY defined
# above or a custom username and API key for authentication. Provide an optional
# id value if you wish to instantiate a particular SoftLayer API object.
#
# Parameters:
# $serviceName - The name of the SoftLayer API service you wish to query.
# $id          - An optional object id if you're instantiating a particular
#                SoftLayer API object. Setting an id defines this client's
#                initialization parameter header.
# $username    - An optional API username if you wish to bypass the package's
#                built-in username.
# $apiKey      - An optional API key if you wish to bypass the package's
#                built-in API key.
# $endpointUrl - The API endpoint base URL you wish to connect to. Set this to
#                $SoftLayer::API::SOAP::API_PRIVATE_ENDPOINT to connect via
#                SoftLayer's private network.
sub new {
    my ($package, $serviceName, $id, $apiUser, $apiKey, $endpointUrl) = @_;
    my $self  = {};

    $self->{headers} = {opt => {}};
    $self->{serviceName} = $serviceName;
    bless($self, $package);

    # Set authentication. Allow the user to override the API username and
    # password defined in this file.
    my $username = undef;
    my $key = undef;

    if ($API_USER eq '') {
        $username = $apiUser;
    } else {
        $username = $API_USER;
    }

    if ($API_KEY eq '') {
        $key = $apiKey;
    } else {
        $key = $API_KEY;
    }

    $self->setAuthentication($username, $key);

    # Default to use the public network API endpoint, otherwise use the endpoint
    # defined in API_PUBLIC_ENDPOINT, otherwise use the one provided by the
    # user.
    if ($endpointUrl ne '') {
        $self->{endpointUrl} = $endpointUrl;
    } elsif ($API_BASE_URL ne '') {
        $self->{endpointUrl} = $API_BASE_URL;
    } else {
        $self->{endpointUrl} = $SoftLayer::API::SOAP::API_PUBLIC_ENDPOINT;
    }

    # Set the init parameter if provided.
    $id = int($id); # This generates a warning if $id is undefined.
    if ($id != 0) {
        $self->setInitParameter($id)
    }

    return $self;
}

# Execute a SoftLayer API call.
sub AUTOLOAD {
    my ($self) = @_;
    shift;

    my @methodParts = split(/::/, $AUTOLOAD);
    my $methodName = pop(@methodParts);

    # Don't do try to make a call if we're tearing the object down.
    if ($methodName ne 'DESTROY') {
        # Set up the SOAP client first.
        my $soapEndpoint = $self->{endpointUrl} . $self->{serviceName};
        my $soapClient = SOAP::Lite->endpoint($soapEndpoint)->proxy($soapEndpoint);
        my $serializer = $soapClient->serializer();
        $serializer->register_ns('http://api.service.softlayer.com/soap/v3/', 'slapi');

        # Convert the headers hash into XML and then into a SOAP::Header.
        # hash2xml seems to only want to work on the first element of a hash, so
        # put all of our headers into an "opt" hash, then strip out the XML
        # declaration and <opt></opt> tags after converting.
        my $headersXml = hash2xml $self->{headers};
        $headersXml =~ s/^\<\?xml.*\?\>\n//;
        $headersXml =~ s/^\<opt\>//;
        $headersXml =~ s/\<\/opt\>$//;

        my $headers = SOAP::Header->type('xml', $headersXml);

        # Define the method to call.
        my $method = SOAP::Data->name('slapi:' . $methodName);

        # Finally, call the method.
        return $soapClient->call($method, @_, $headers);
    }
}

# Set a SoftLayer API call header
#
# Every header defines a customization specific to an SoftLayer API call. Most
# API calls require authentication and initialization parameter headers, but can
# also include optional headers such as object masks and result limits if
# they're supported by the API method you're calling.
#
# Parameters:
# $name   - The name of the header you wish to set.
# \%value - The data you wish to set in this header.
sub setHeader {
    my($self, $name, $value) = @_;
    $self->{headers}{opt}{'slapi:' . $name} = $value;
}

# Remove a SoftLayer API call header
#
# Removing headers may cause API queries to fail.
#
# Parameters:
# $name - The name of the header you wish to remove.
sub removeHeader {
    my($self, $name) = @_;
    delete $self->{headers}{opt}{'slapi:' . $name};
}

# Set a user and key to authenticate a SoftLayer API call
#
# Use this method if you wish to bypass the $API_USER and $API_KEY variables in
# this package and set custom authentication per API call. Head to
# <https://manage.softlayer.com/Administrative/apiKeychain> to manage your API
# keys in the SoftLayer customer portal.
#
# Parameters:
# $username - The username you wish to authenticate with.
# $apiKey   - Your user's API key.
sub setAuthentication {
    my($self, $username, $apiKey) = @_;

    $self->setHeader('authenticate', {
        username => $username,
        apiKey => $apiKey
    });
}

# Set an initialization parameter header on a SoftLayer API call
#
# Initialization parameters instantiate a SoftLayer API service object to act
# upon during your API method call. For instance, if your account has a server
# with id number 1234, then setting an initialization parameter of 1234 in the
# SoftLayer_Hardware_Server Service instructs the API to act on server record
# 1234 in your method calls. See
# <http://sldn.softlayer.com/wiki/index.php/Using_Initialization_Parameters_in_the_SoftLayer_API>
# for more information.
#
# Parameters:
# $id - The ID number of the SoftLayer API object you wish to instantiate.
sub setInitParameter {
    my($self, $id) = @_;

    $self->setHeader($self->{serviceName} . 'InitParameters', {
        id => int($id)
    });
}

# Set an object mask to a SoftLayer API call
#
# Use an object mask to retrieve data related your API call's result. Object
# masks are skeleton objects that define nested relational properties to
# retrieve along with an object's local properties. See
# <http://sldn.softlayer.com/wiki/index.php/Using_Object_Masks_in_the_SoftLayer_API>
# for more information.
#
# Parameters:
# $mask - The object mask you wish to define
sub setObjectMask {
    my($self, $objectMask) = @_;

    $self->setHeader($self->{serviceName} . 'ObjectMask', {
        'mask' => $objectMask
    });
}

# Set a result limit on a SoftLayer API call
#
# Many SoftLayer API methods return a group of results. These methods
# support a way to limit the number of results retrieved from the SoftLayer
# API in a way akin to an SQL LIMIT statement. See
# <http://sldn.softlayer.com/wiki/index.php/Using_Result_Limits_in_the_SoftLayer_API>
# for more information.
#
# Parameters:
# $limit  - The number of results to limit your SoftLayer API call to.
# $offset - An optional offset to begin your SoftLayer API call's returned
#           result set at.
sub setResultLimit {
    my($self, $limit, $offset) = @_;

    $self->setHeader('resultLimit', {
        limit => int($limit),
        offset => int($offset)
    });
}

1;
__END__
=head1 NAME

SoftLayer::API::SOAP - A Perl extension to communicate with the SoftLayer API

=head1 DESCRIPTION

SoftLayer::API::SOAP provides a simple method for connecting to and making calls from the SoftLayer SOAP API and provides support for many of the SoftLayer API's features.

SOAP method calls and client management are handled by the L<SOAP::Lite> module with some help from L<XML::Hash::LX>. Please install both of these modules before using SoftLayer::API::SOAP. Place the SoftLayer directory this file is contained in somewhere within your system's C<@INC> path or use the C<use lib> statement to include a custom path.

Follow these steps to make a SoftLayer API call:

1) Declare a new API object by calling the C<SoftLayer::API::SOAP->new()> method. This method has one required parameter and three optional parameters:

=over

=item * serviceName: The name of SoftLayer API service you wish to use like 'SoftLayer_Account' or 'SoftLayer_Hardware_Server'.

=item * initParameter: An optional id to initialize your API client with a specific object.

=item * username: Your SoftLayer API username. You can either specify it when calling C<new()> or define it in the C<SOAP.pm> file.

=item * apiKey: Your SoftLayer API key. You can either specify it when calling C<new()> or define it in the C<SOAP.pm> file.

=item * endpointUrl: An optional API endpoint URL if you do not wish to call SoftLayer's public network API endpoints. Pass the value $SoftLayer::API::SOAP::API_PRIVATE_ENDPOINT if you wish to connect to SoftLayer's private network API endpoints.
=back

 my $client = SoftLayer::API::SOAP->new('SoftLayer_Account');
 my $client = SoftLayer::API::SOAP->new('SoftLayer_Hardware_Server', $serverId, $username, $apiKey);

2) Call a method from your API client object corresponding to the SoftLayee API method you wish to call, specifying parameters as needed.

 my $openTickets = $client->getOpenTickets();

3) Check for errors by checking the C<< ->fault >> property on your API call result. If C<< ->fault >> is set then C<< ->faultstring >> contains the error message received from the SoftLayer API. Otherwise, the result of your API call is stored in the C<< ->result >> property.

 if ($openTickets->fault) {
     echo $openTickets->faultstring;
 } else {
     echo 'I have tickets!';
     print Dumper($openTickets->result);
 }

These steps can be combined on a single line:

 my $openTickets = SoftLayer::API::SOAP->new('SoftLayer_Account')->getOpenTickets()->result;

=head1 USAGE

Here's a simple usage example that retrieves account information by calling the C<getObject()> method in the C<SoftLayer_Account> service:

 # This is optional and can be removed if you already have the SoftLayer
 # directory that contains this module in your @INC path.
 use lib '/path/to/my/SoftLayer/directory';

 use SoftLayer::API::SOAP;
 use Data::Dumper;

 # Initialize an API client for the SoftLayer_Account service.
 my $client = SoftLayer::API::SOAP->new('SoftLayer_Account');

 # Retrieve our account record
 my $account = $client->getObject();

 if ($account->fault) {
     die 'Unable to retrieve account information: ' . $account->faultstring;
 } else {
     print Dumper($account->result);
 }

For a more complex example we'll retrieve a support ticket with id 123456 along with the ticket's updates, the user it's assigned to, the servers attached to it, and the datacenter those servers are in. We'll retrieve our extra information using a nested object mask. After we have the ticket we'll update it with the text 'Hello!'.

 use SoftLayer::API::SOAP;
 use Data::Dumper;

 # Initialize an API client for ticket 123456
 my $client = SoftLayer::API::SOAP->new('SoftLayer_Ticket', 123456);

 # Assign an object mask to our API client.
 $client->setObjectMask({
     updates => '',
     assignedUser => '',
     attachedHardware => {
         datacenter => ''
     }
 });

 # Retrieve the ticket record
 my $ticket = $client->getObject();

 if ($ticket->fault) {
     die 'Unable to retrieve ticket record: ' . $ticket->faultstring;
 } else {
     print Dumper($ticket->result);
 }

 # Update the ticket
 my %update = {
     entry => 'Hello!'
 };

 my $ticketUpdate = $client->addUpdate($update);

 if ($ticketUpdate->fault) {
     die 'Unable to update ticket: ' . $ticketUpdate->faultstring;
 } else {
     print "Updated ticket 123456. The new update's id is "
         . $ticketUpdate->result->{'id'} . '.';
 }

=head1 SEE ALSO

=begin html

The most up to date version of this library can be found on the SoftLayer github <a href="http://github.com/softlayer">public repositories</a>. Please post to the <a href="http://forums.softlayer.com/">SoftLayer forums</a> or open a support ticket in the SoftLayer customer portal if you have any questions regarding use of this library.

=end html

=head1 AUTHOR

SoftLayer Technologies, Inc. E<lt>sldn@softlayer.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2010, SoftLayer Technologies, Inc. All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

=over

=item * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

=item * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

=item * Neither SoftLayer Technologies, Inc. nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

=back

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
=cut
