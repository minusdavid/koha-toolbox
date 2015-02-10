#!/usr/bin/perl

use Modern::Perl;
use Text::CSV::Encoded;
use Term::ANSIColor;
use Getopt::Long;

=head1 USAGE

perl permissions_from_sql.pl --dir "/home/koha/git/installer"
perl permissions_from_sql.pl --dir "/home/koha/git/installer/data/mysql/pl-PL" -v --debug

=cut

#######################################################################
#Define variables

my $error_counter = 0;
my $verbose = 0;
my $debug = 0;
my $csv = Text::CSV::Encoded->new({
    quote_char => "'",
    escape_char => "'",
    allow_whitespace => 1,
    encoding => 'utf8',
});

my $installer_dir = '';
my @file_list = ("userflags","userpermissions");

GetOptions(
    "dir=s" => \$installer_dir,
    "v" => \$verbose,
    "debug" => \$debug,
) or die ("Error in command line arguments\n");

my $master_hash = {};

#######################################################################
#Script action

my $command = qq(find $installer_dir -name "userflags.sql" -o -name "userpermissions.sql");
$debug && say "Command = $command";

#Find all the SQL permission files you'll need to parse...
my @permissions_files = `$command`;

foreach my $permissions_file (@permissions_files){
    $verbose && say "Filepath = $permissions_file"; 
    my $language_code = '';
    my $filename = '';
    if ($permissions_file =~ /.*\/installer\/data\/mysql\/(.*)\/.*\/(.*)\.sql/){
            $language_code = $1;
            $filename = $2;
            $verbose && say "Language code = $language_code" if $language_code;
            $verbose && say "Filename = $filename" if $filename;
    }   
    my $permissions = parse_sql_for_values({
        file => $permissions_file,
    });
    if (@$permissions && $language_code && $filename){
        $master_hash->{$language_code}->{$filename} = $permissions;
    }
}


foreach my $language_key (keys %$master_hash){
    
    #Write to file
    my $output_file = "permissions_$language_key.inc";
    open(my $output_fh, '>', $output_file) or die "Could not open file '$output_file' $!";
    
    #NOTE: Force the order to go from "main_permissions" to "sub_permissions" using this array
    foreach my $file_key (@file_list){
        my $permission_array = $master_hash->{$language_key}->{$file_key};
        if (ref $permission_array eq 'ARRAY'){
            my $block_name = '';
            if ($file_key eq 'userflags'){
                $block_name = 'main_permissions';
            } elsif ($file_key eq 'userpermissions'){
                $block_name = 'sub_permissions';
            }
            my $block = create_block({
                permissions => $permission_array,
                block_name => $block_name,
                switch_variable => 'name',   
            });
            print $output_fh $block;
            print $output_fh "\n";
        }
    }
}


my $final_error_count = $error_counter ? colored($error_counter,"red") : colored($error_counter,"green");
print "Number of errors encountered: $final_error_count \n";

#######################################################################
#Define functions

sub parse_sql_for_values {
    my ($params) = @_;
    my $file = $params->{file};
    my $hash_ref = {};
    my $array_ref = [];
    if ($file){
        open(my $fh, $file) or warn "Can't open $file: $!";
        while ( ! eof($fh) ){
            defined(my $line = <$fh>)
                or die "readline failed for $fh: $!";
            if ($line =~ /(^|VALUES)\s*\Q(\E(.*)\Q)\E/){
                my $values = $2;
                if ($values){
                   $values =~ s/\\'/''/g; #Change C-style backslash escape to single quote, double quote escapes are common in SQL and CSV apparently
                   my $status = $csv->parse($values);
                    if($status){
                        my @columns = $csv->fields;
                        push(@$array_ref,\@columns);
                    } else {
                        print colored("There was a problem parsing $values \n","red");
                        $error_counter++;
                    }
                }
            }
        }
    }
    return $array_ref;
}


sub create_block {
    my ($params) = @_;
    my $output = '';
    my $permissions = $params->{permissions};
    my $block_name = $params->{block_name};
    my $switch_variable = $params->{switch_variable};

    $output .= "[% - BLOCK $block_name -%]\n";
    $output .= "[% SWITCH $switch_variable %]\n";
    foreach my $permission (@$permissions){
        my $case = $permission->[1];
        my $description = $permission->[2];
        $output .= "[%- CASE '".$case."' -%]\n";
        $output .= "$description\n";
    }
    $output .= "[%- CASE -%]\n";
    $output .= "[%- END -%]\n";
    $output .= "[%- END -%]\n";

    return $output;
}
