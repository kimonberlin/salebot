package Tables;

use strict;
use warnings;
use utf8;
use base 'Class::DBI';


use ConfigFile;

config_init();
die "revision_table not defined" unless $config->{revision_table};
       
# Here we create our 'main' connection
# to the database
Tables->connection( "dbi:mysql:database=$config->{db_name}:host=$config->{db_server}",
    $config->{db_user}, $config->{db_pass} );


1;

#----------------------------------------------------------------------------

package Table::User;
use base 'Tables';
use ConfigFile;

Table::User->table( $config->{user_table} );

# important side note -
# the All creation method only works correctly if the FIRST field
# in the table is a primary, use the Primary assignment method
# outlined in the docs if this is the case

Table::User->columns(
    All =>
      qw/name
      user_id
      creation_time
      last_action_time
      last_page
      action_count
      edit_count
      new_page_count
      vandalism_total
      reverted_by_human_count
      warn_edit_count
      spam_total
      rollback_made_count
      bot_revert_count
      bot_impossible_revert_count
      ignore_user
      stop_edits
      is_proxy
      fqdn
      whitelist_exp_time
      recent_move_count
      last_reverted_time
      last_move_time
      last_edit_time
      recent_edit_count
      spam_count
      last_spam_time
      bot_block_exp_time
      watchlist_exp_time
      last_trusted_reverted_time/
);
# 'name' is primary key

sub rehabilitate
{
    my ($name) = @_;
    
    my $user = Table::User->retrieve($name);
    return unless $user;
    $user->ignore_user (1);    
    $user->vandalism_total (0);
    $user->stop_edits (0);
    $user->update;
}
1;

#----------------------------------------------------------------------------

package Table::Revision;

use base 'Tables';
use ConfigFile;

Table::Revision->table( $config->{revision_table} );
Table::Revision->columns( All => qw/revision page user diff_url patrolled rcid/ );
# 'revision' is primary key

1;

#----------------------------------------------------------------------------

package Table::Reverts;

use base 'Tables';
use ConfigFile;

Table::Reverts->table( $config->{revert_table} );
Table::Reverts->columns(
    All =>
      qw(page user timestamp rc_text)
);

#
# get_wronged_user() returns the name of the last user reverted by Salebot on page
#
sub get_wronged_user
{
    my ( $page ) = @_;

    my @reverts = Table::Reverts->search(page => $page, {order_by=>'timestamp DESC'});
    return unless @reverts;
    my $rv = $reverts[0];
    return $rv->user;
}

1;

#----------------------------------------------------------------------------

package Table::Page;

use base 'Tables';
use ConfigFile;

Table::Page->table( $config->{page_table} );
Table::Page->columns(
    All =>
      qw(page creator creation_time deletion_time deletion_summary)
);

1;

#----------------------------------------------------------------------------
