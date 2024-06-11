#!/usr/bin/perl

binmode( STDOUT, ":utf8" );

#Script to call Google Lighthouse API and gather Gtmetrix style details
use strict;
use warnings;
use LWP::UserAgent;
use JSON qw(decode_json encode_json);
use URI::Escape;
use utf8;
use Text::Table;
use Term::ANSIColor;
use feature qw(say);
use Data::Dumper;
use Getopt::Long;
use Fcntl ':mode';
use Mozilla::CA;

my $field_color = color("bold yellow");
my $value_color = color("yellow");
my $reset       = color("reset");

# Configuration file path
my $config_file = 'LightHouseAPI.json';

# Flags for command line options
my $api_key_flag;
my $update_key;

GetOptions("api=s" => \$api_key_flag);

# Function to read API key from configuration file
sub read_api_key {
    if (-e $config_file) {
        open my $fh, '<', $config_file or die "Cannot open $config_file: $!";
        my $config_data = do { local $/; <$fh> };
        close $fh;
        my $config = decode_json($config_data);
        return $config->{'api_key'};
    }
    return;
}

# Function to write API key to configuration file
sub write_api_key {
    my ($api_key) = @_;
    open my $fh, '>', $config_file or die "Cannot open $config_file: $!";
    print $fh encode_json({ api_key => $api_key });
    close $fh;
    # Set file permissions to ensure it is readable and writable by the user
    chmod 0600, $config_file or die "Cannot chmod $config_file: $!";
}

# Update the API key if the --api flag is provided
if ($api_key_flag) {
    write_api_key($api_key_flag);
    print "API key updated and saved to $config_file\n";
    exit 0;
}

# Read the API key from the configuration file
my $api_key = read_api_key();

# Show usage if no API key is set
unless ($api_key) {
    die "First Usage or Update API key only: $0 --api <API_KEY>\n";
}

# Check if a domain was passed as an argument
my $original_url = $ARGV[0];
unless ($original_url) {
    die "Usage: $0 <domain>\n";
}

unless ($original_url =~ m!^https?://!) {
    $original_url = "https://$original_url";
}
die "Invalid URL" unless $original_url =~ m!^https?://[\w.-]+\.\w+(:\d+)?(/|$)!;

# URL encode the site URL for API usage
my $site_url = uri_escape($original_url);

my $api_endpoint =
  "https://www.googleapis.com/pagespeedonline/v5/runPagespeed?url=$site_url&key=$api_key&strategy=desktop";

my $ua = LWP::UserAgent->new;
$ua->timeout(120);

# Initial API request
my $response = $ua->get($api_endpoint);
if (!$response->is_success) {
    warn "Initial API call failed: " . $response->status_line;
    say "Testing Server HTTP status...";
    my $http_status = check_site_availability();
    if ($http_status eq '200') {
        warn "Server is up (HTTP code $http_status), proceeding with retries...\n";
        retry_api();
    } else {
        die "\nServer reported HTTP status $http_status, Not going to retry.\n";
    }
}

sub check_site_availability {
    my $curl_status = `curl -o /dev/null -s -w "%{http_code}" -I '$original_url'`;
    chomp($curl_status);
    return $curl_status;
}

sub retry_api {
    my $max_retries = 4;  # Including the initial attempt
    my $retry_count = 1;  # Start counting retries from 1

    while ($retry_count < $max_retries) {
        warn "Attempting retry $retry_count...\n";
        my $response = $ua->get($api_endpoint);
        if ($response->is_success) {
            my $content = decode_json($response->decoded_content);
            print Dumper($content);
            return;
        } else {
            warn "Retry $retry_count failed: " . $response->status_line . "\n";
            $retry_count++;
            if ($retry_count < $max_retries) {
                warn "Retrying API call in 3 seconds...\n";
                sleep(3);
            }
        }
    }
    die "Failed to fetch after $max_retries attempts.\n";
}

# Define known keys and how to format them
my %key_handlers = (
    'numericValue'     => sub { return defined $_[0] ? $_[0] : 'N/A'; },
    'displayValue'     => sub { return $_[0]; },
    'score'            => sub { return defined $_[0] ? $_[0] : 'N/A'; },
    'title'            => sub { return defined $_[0] ? $_[0] : 'N/A'; },
    'overallSavingsMs' => sub { return defined $_[0] ? $_[0] : 'N/A'; },
);

my %size_by_type;
my %count_by_type;
my $total_size     = 0;
my $total_requests = 0;

# Check the response
if ( $response->is_success ) {
    my $data = decode_json( $response->decoded_content );

    if ( exists $data->{lighthouseResult}{audits} ) {
        my $audits = $data->{lighthouseResult}{audits};

        my @metrics = (
            {
                key    => 'server-response-time',
                fields => [ 'description', 'displayValue' ],
                label  => 'TTFB',
            },
            {
                key    => 'interactive',
                fields => [ 'description', 'displayValue' ],
                label  => 'Full Load Time',
            },
            {
                key    => 'first-contentful-paint',
                fields => [ 'displayValue', 'description' ],
                label  => 'FCP',
            },
            {
                key    => 'largest-contentful-paint',
                fields => [ 'description', 'displayValue' ],
                label  => 'LCP',
            },
            {
                key    => 'uses-responsive-images',
                fields => ['description', 'displayValue'],
                label  => 'Properly size images ',
            },
            {
                key    => 'unminified-css',
                fields => [ 'description', 'overallSavingsBytes' ],
                label  => 'Minify CSS',
            },
            {
                key    => 'unminified-javascript',
                fields => [ 'description', 'overallSavingsBytes' ],
                label  => 'Minify JS',
            },
            {
                key    => 'unused-javascript',
                fields => [ 'description', 'overallSavingsBytes' ],
                label  => 'Unused JS',
            },
            {
                key    => 'unused-css-rules',
                fields => [ 'description', 'overallSavingsBytes' ],
                label  => 'Unused CSS',
            },
                        {
                key    => 'total-byte-weight',
                fields => [ 'description', 'numericValue' ],
                label  => 'Total Page Size',
            },
            {
                key    => 'network-requests',
                fields => ['description'],
                label  => 'Total Requests',
            },

        );

        my $tb = Text::Table->new(
            { title => "\nMetric",      align => 'left' },
            { title => "\nValue",       align => 'left' },
            { title => "\nExplanation", align => 'left' },
        );

        foreach my $metric (@metrics) {
            my %fields_values;
            my $display_value = 'N/A';
            my $description   = 'N/A';

            foreach my $field ( @{ $metric->{fields} } ) {
                if ( exists $audits->{ $metric->{key} }->{$field} ) {
                    $fields_values{$field} =
                      $audits->{ $metric->{key} }->{$field};
                }
            }

            if ( exists $fields_values{'description'} ) {
                $description = $fields_values{'description'};

        # This regex matches the markdown link format and captures the URL in $1
                if ( $description =~ /\[.*?\]\((http[s]?:\/\/[^\)]+)\)/ ) {
                    $description = $1; # Contains the URL from the markdown link
                }
            }

            if ( $metric->{key} eq 'network-requests' ) {
                if (   exists $audits->{'network-requests'}
                    && exists $audits->{'network-requests'}->{details}->{items}
                  )
                {
                    my $requests =
                      $audits->{'network-requests'}->{details}->{items};
                    $total_requests = scalar @{$requests};

                    foreach my $req ( @{$requests} ) {
                        next
                          if !exists $req->{transferSize}
                          || !exists $req->{resourceType};

                        $size_by_type{ $req->{resourceType} } +=
                          $req->{transferSize};
                        $count_by_type{ $req->{resourceType} }++;
                    }

                    $total_size = 0;
                    $total_size += $size_by_type{$_} for keys %size_by_type;
                    $display_value = $total_requests;
                }

            }
            elsif ($metric->{key} eq 'server-response-time') {
                if (defined $audits->{'server-response-time'}->{numericValue}) {
                    my $response_time_in_ms = $audits->{'server-response-time'}->{numericValue};
                    # Convert milliseconds to seconds
                    my $response_time_in_s = $response_time_in_ms / 1000;
                    $display_value = sprintf("%.3f seconds", $response_time_in_s);
                } else {
                    $display_value = 'N/A';
                }
            }
            elsif ( $metric->{key} eq 'total-byte-weight' ) {

                # Convert from bytes to MB by dividing by (1024 * 1024)
                if ( defined $audits->{'total-byte-weight'}->{numericValue} ) {
                    $display_value = sprintf( "%.2f MB",
                        $audits->{'total-byte-weight'}->{numericValue} /
                          ( 1024 * 1024 ) );
                }
                else {
                    $display_value = 'N/A';
                }
            }
            elsif ( $metric->{key} eq 'unminified-css' ) {

                # Check if the overallSavingsBytes value is defined
                if (
                    defined $audits->{'unminified-css'}->{details}
                    ->{overallSavingsBytes} )
                {
                    # Convert from bytes to KB
                    my $savings_bytes =
                      $audits->{'unminified-css'}->{details}
                      ->{overallSavingsBytes};
                    my $savings_kb = $savings_bytes / 1024;
                    $display_value =
                      sprintf( "Potential Savings %.2f KB", $savings_kb );
                }
                else {
                    $display_value = 'N/A';
                }
            }
            elsif ( $metric->{key} eq 'unminified-javascript' ) {

                # Check if the overallSavingsBytes value is defined
                if (
                    defined $audits->{'unminified-javascript'}->{details}
                    ->{overallSavingsBytes} )
                {
                    # Convert from bytes to KB
                    my $savings_bytes =
                      $audits->{'unminified-javascript'}->{details}
                      ->{overallSavingsBytes};
                    my $savings_kb = $savings_bytes / 1024;
                    $display_value =
                      sprintf( "Potential Savings %.2f KB", $savings_kb );
                }
                else {
                    $display_value = 'N/A';
                }
            }
            elsif ( $metric->{key} eq 'unused-javascript' ) {

                # Check if the overallSavingsBytes value is defined
                if (
                    defined $audits->{'unused-javascript'}->{details}
                    ->{overallSavingsBytes} )
                {
                    # Convert from bytes to KB
                    my $savings_bytes =
                      $audits->{'unused-javascript'}->{details}
                      ->{overallSavingsBytes};
                    my $savings_kb = $savings_bytes / 1024;
                    $display_value =
                      sprintf( "Potential Savings %.2f KB", $savings_kb );
                }
                else {
                    $display_value = 'N/A';
                }
            }
            elsif ( $metric->{key} eq 'unused-css-rules' ) {

                # Check if the overallSavingsBytes value is defined
                if (
                    defined $audits->{'unused-css-rules'}->{details}
                    ->{overallSavingsBytes} )
                {
                    # Convert from bytes to KB
                    my $savings_bytes =
                      $audits->{'unused-css-rules'}->{details}
                      ->{overallSavingsBytes};
                    my $savings_kb = $savings_bytes / 1024;
                    $display_value =
                      sprintf( "Potential Savings %.2f KB", $savings_kb );
                }
                else {
                    $display_value = 'N/A';
                }
            }
            elsif ( $metric->{key} eq 'uses-responsive-images' ) {

                # Check if the overallSavingsBytes value is defined
                if (
                    defined $audits->{'uses-responsive-images'}->{details}
                    ->{overallSavingsBytes} )
                {
                    # Convert from bytes to KB
                    my $savings_bytes =
                      $audits->{'uses-responsive-images'}->{details}
                      ->{overallSavingsBytes};
                    my $savings_kb = $savings_bytes / 1024;
                    $display_value =
                      sprintf( "Potential Savings %.2f KB", $savings_kb );
                }
                else {
                    $display_value = 'N/A';
                }
            }
            else {
                # Process other metrics normally
                foreach my $field ( @{ $metric->{fields} } ) {
                    if ( exists $audits->{ $metric->{key} }->{$field} ) {
                        $fields_values{$field} =
                          $audits->{ $metric->{key} }->{$field};
                    }
                }

                # # Extract the description and shorten it
                if ( exists $fields_values{'description'} ) {
                    $description = $fields_values{'description'};

        # This regex matches the markdown link format and captures the URL in $1
                    if ( $description =~ /\[.*?\]\((http[s]?:\/\/[^\)]+)\)/ ) {
                        $description =
                          $1;    # Contains the URL from the markdown link
                    }

                }

                # Determine the display value based on available data
                foreach my $key ( sort keys %key_handlers ) {
                    if ( defined $fields_values{$key} ) {
                        $display_value =
                          $key_handlers{$key}->( $fields_values{$key} );
                        last;
                    }
                }
            }

            my $metric_label = $metric->{label}
              // ucfirst( join ' ', map { lc } split /-/, $metric->{key} );

            # Add the row to the table
            my @row = ( $metric_label, $display_value, $description, );

            # Apply color to 'Metric' and 'Value' only
            $row[0] = $field_color . $row[0] . $reset;
            $row[2] = $value_color . $row[2] . $reset;

            $tb->add(@row);
        }

        say "\n:: Google Lighthouse PageSpeed Insights API ::";
        print $tb;

        # Before your print statements to show the header
        print "\nPage Details:\n";
        printf "%-20s | %7s | %15s | %8s\n", "Resource Type", "Count",
          "Size (MB)", "Percentage of Bytes";
        printf "%-20s | %7s | %15s | %8s\n", "-" x 20, "-" x 7, "-" x 15,
          "-" x 24;
        
        foreach my $type ( sort keys %size_by_type ) {
            my $display_type = $type;
            $display_type = "CSS" if $type eq 'Stylesheet';
            $display_type = "JS"  if $type eq 'Script';

            # Calculate the size in MB and format it to 2 decimal places
            my $size_in_mb = $size_by_type{$type} / ( 1024**2 );

            printf "%-20s | %7d | %15.2f | %8.2f%%\n",
              $display_type,
              $count_by_type{$type},
              $size_in_mb,
              $size_by_type{$type} / $total_size * 100;
        }
        say "-" x 75;
        say "";

    }
    else {
        say "No Lighthouse data available for $site_url.";
    }
}
else {
    say "Failed to retrieve data: ", $response->status_line;
}

