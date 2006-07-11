# $Id$

# object to hold NCBI score information, links, booleans, and other info
# from elink queries; API to change dramatically

# this should hold all the linksets for one group of IDs and should
# eventually accomodate all cmd types.

package Bio::DB::EUtilities::ElinkData;
use strict;
use warnings;

use Bio::Root::Root;
#use Data::Dumper;
use vars '@ISA';

@ISA = 'Bio::Root::Root';

sub new {
    my ($class, @args) = @_;
    my $self = $class->SUPER::new(@args);
    my ($command) = $self->_rearrange([qw(COMMAND)], @args);
    $command    && $self->command($command);
    $self->{'_dbindex'} = 0;
    $self->{'_scoreindex'} = 0;
    $self->{'_scoredb_key'} = '';
    return $self;
}

# this should make a deep copy of the XML data for each ElinkData Linkset

sub _add_set {
    my $self = shift;
    $self->throw('No linkset!') unless my $ls = shift;
    my $dbfrom = $ls->{DbFrom};
    $self->dbfrom($dbfrom);
    my $query_ids = $ls->{IdList}->{Id};
    if (!ref($query_ids)) {
        my $tempid = $query_ids;
        $query_ids = [$tempid];
    }
    $self->query_ids($query_ids);
    for my $ls_db (@{ $ls->{LinkSetDb} }) {
        my $dbto = $ls_db->{DbTo};
        push @{ $self->{'_databases'}}, $dbto;
        my $linkname = $ls_db->{LinkName};
        if ( $ls_db->{Info} || $ls->{ERROR} || !($ls_db->{Link})) {
            my $err_msg = $ls_db->{Info} || $ls->{ERROR} || 'No Links!';
            my $ids = (ref($query_ids) =~ /array/i) ?
                            join q(,), @{$query_ids}: $query_ids;
            $self->warn("ELink Error for $dbto and ids $ids: $err_msg");
            next;
        }
        my @ids;
        for my $id_ref (@{ $ls_db->{Link} } ) {
            my $id = $id_ref->{Id};
            my $score = $id_ref->{Score} ? $id_ref->{Score} : undef;
            push @ids, $id;
            # set up in case there are multiple databases that return scores
            if ($score) {
                $self->{'_scores'}->{$dbto}->{$id} = $score;
                if (!($self->{'_has_scores'})) {
                    push @{ $self->{'_has_scores'} }, $dbto;
                }
            }
        }
        my $linkset = {
                       'LinkName' => $linkname,
                       'DbTo'     => $dbto,
                       'Id'       => \@ids,
                      };
        #$self->debug('Linkset:',Dumper($linkset));
        push @{ $self->{'_linksetdb'}}, $linkset;    
    }
}

=head2 dbfrom

 Title   : dbfrom
 Usage   : $dbfrom = $linkset->dbfrom;
 Function: gets/sets dbfrom value
 Returns : originating database
 Args    : originating database

=cut

sub dbfrom {
    my $self = shift;
    return $self->{'_dbfrom'} = shift if @_;
    return $self->{'_dbfrom'};
}

=head2 query_ids

 Title   : query_ids
 Usage   : @ids = $linkset->query_ids;
 Function: gets/sets original query ID values (ref to array)
 Returns : array or array ref of IDs (based on wantarray)
 Args    : array ref of IDs

=cut

sub query_ids {
    my $self = shift;
    return $self->{'_query_ids'} = shift if @_;
    return @{ $self->{'_query_ids'} } if wantarray;
    return $self->{'_query_ids'};
}

=head2 command

 Title   : command
 Usage   : $cmd = $linkset->command;
 Function: gets/sets cmd used for elink query
 Returns : string (cmd parameter)
 Args    : string (cmd parameter)

=cut

sub command {
    my $self = shift;
    return $self->{'_command'} = shift if @_;
    return $self->{'_command'};
}

=head2 get_LinkIds_by_db

 Title   : get_LinkIds_by_db
 Usage   : @ids = $linkset->get_LinkIds_by_db('protein');
 Function: retrieves primary ID list based on the database for the object
 Returns : array or array ref of IDs (based on wantarray)
 Args    : None

=cut

sub get_LinkIds_by_db {
    my $self = shift;
    my $db = shift if @_;
    $self->throw("Must use database to access IDs") if !$db;
    for my $linkset (@{ $self->{'_linksetdb'}}) {
        my $dbto = $linkset->{DbTo};
        if ($dbto eq $db) {
            return @{ $linkset->{Id} } if wantarray;
            return $linkset->{Id};
        }
    }
    $self->warn("Couldn't find ids for database $db");
}

=head2 next_database

 Title   : next_database
 Usage   : while (my $db = $linkset->next_database) {
 Function: iterates through list of database names in internal queue
 Returns : String (name of database)
 Args    : None

=cut

sub next_database {
    my $self = shift;
    my $index = $self->_next_db_index;
    return if ($index > scalar($self->{'_databases'}));
    return $self->{'_databases'}->[$index] ;
}

=head2 get_all_databases

 Title   : get_all_databases
 Usage   : @dbs = $linkset->get_all_databases;
 Function: returns all database names which contain IDs
 Returns : array or array ref of databases (based on wantarray)
 Args    : None

=cut

sub get_all_databases {
    my $self = shift;
    return @{ $self->{'_databases'} } if wantarray;
    return $self->{'_databases'};
}

=head2 next_scoredb

 Title   : next_scoredb
 Usage   : while (my $db = $linkset->next_scoredb) {
 Function: iterates through list of database with score values
 Returns : String (name of database)
 Args    : None

=cut

sub next_scoredb {
    my $self = shift;
    my $index = $self->_next_scoredb_index;
    return if ($index > scalar($self->{'_has_scores'}));
    my $db = $self->{'_has_scores'}->[$index];
    $self->set_scoredb($db);
    return $db;
}

=head2 get_all_scoredbs

 Title   : get_all_scoredbs
 Usage   : @dbs = $linkset->get_all_scoredbs;
 Function: returns database names which contain scores
 Returns : array or array ref of databases (based on wantarray)
 Args    : None

=cut

sub get_all_scoredbs {
    my $self = shift;
    return @{ $self->{'_has_scores'} } if wantarray;
    return $self->{'_has_scores'}->[0];
}

=head2 get_score

 Title   : get_score
 Usage   : $score = $linkset->get_score($id);
 Function: returns score value for ID
 Returns : score value
 Args    : ID
 Note    : if multiple databases are returned with scores (rare but possible),
         : you must set the default score database using set_scoredb.  If you
         : use next_scoredb to iterate through the databases, this is done for you

=cut

sub get_score {
    my $self = shift;
    my $id = shift if @_;
    if (!$self->get_all_scoredbs) {
        $self->warn("No scores!");
        return;
    }
    if (!$id) {
        $self->warn("Must use ID to access scores");
    }
    my ($db) = $self->{'_scoredb'} ? $self->{'_scoredb'} : $self->get_all_scoredbs;
    if ( $self->{'_scores'}->{$db}->{$id} ) {
        return $self->{'_scores'}->{$db}->{$id};
    }
}

=head2 get_score_hash

 Title   : get_score_hash
 Usage   : %scores = $linkset->get_score_hash($database);
 Function: returns ID(key)-score(value) hash based on database name
 Returns : score value
 Args    : OPTIONAL : database name.  If there is only one score hash, returns
         : that hash, otherwise throws an exception

=cut

sub get_score_hash {
    my $self = shift;
    $self->warn("No scores!") if !$self->has_scores;
    my $db = $self->{'_scoredb'} ? $self->{'_scoredb'} : $self->get_all_scoredbs;
    if ($self->{'_scores'}->{$db}) {
        return %{ $self->{'_scores'}->{$db} };
    }
}

=head2 set_scoredb

 Title   : set_scoredb
 Usage   : $linkset->set_scoredb('protein');
 Function: sets the database to retrieve scores from
 Returns : None
 Args    : database name

=cut

sub set_scoredb {
    my ($self, $key) = shift;
    $self->{'_scoredb'} if $key;
}

=head2 rewind_databases

 Title   : rewind_databases
 Usage   : $linkset->rewind_databases;
 Function: resets the iterator for next_database
 Returns : None
 Args    : None

=cut

sub rewind_databases {
    my $self = shift;
    $self->{'_dbindex'} = 0;
}

=head2 rewind_scoredbs

 Title   : rewind_scoredbs
 Usage   : $linkset->rewind_scoredbs;
 Function: resets the iterator, current database for next_scoredb
 Returns : None
 Args    : None

=cut

sub rewind_scoredbs {
    my $self = shift;
    $self->{'_scoreindex'} = 0;
    $self->{'_scoredb'} = '';
}

# private methods

#iterator for full database list
sub _next_db_index {
    my $self = shift;
    return $self->{'_dbindex'}++;
}

#iterator for score database list
sub _next_scoredb_index {
    my $self = shift;
    return $self->{'_scoreindex'}++;
}



1;
__END__