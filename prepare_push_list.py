import csv
import logging
import datetime

import yaml


logger = logging.getLogger('push_list')
# these filenames are also hardcoded in extractADevents.ps1 file
# make sure they point to same filenames
EVENTS_FILE_PATH = 'events.csv'
PUSH_FILE_PATH = 'push_list.csv'
# absolute path needed if script not in same location as UST
UST_FILE_PATH = 'user-sync-config.yml'
# use absolute path, including ending slash
# example for Win: 'C:\\path\\to_UST_folder\\logs\\'
LOGS_FOLDER = ''
date = datetime.datetime.now()
LOG_FILE_NAME = 'push-' + '{}-{}-{}'.format(date.year, date.month, date.day) + '.log'


class UMAPI_PUSH(object):
    """
    this class is used to manage the AD extraction of events from audit log
    and to obtain the final input csv file for User Sync Tool to be run 
    with its '--strategy push --users list csv_file' arguments
    """
    def __init__(self):
        self.logger = logger
        self.push_list = {}
        self.disabled_accounts = {}
        self.logger.info('-----preparing push list-----')

    def user_init(self, row):
        """
        picks up the csv row data and adds them into a dict object
        if any custom attribute needs to replace any user key, use
        the appropiate row['customAttribute1-4'] from events file
        returns: {dict} object
        """
        user = {}
        user['email'] = row['email']
        if not user['email'] or '@' not in user['email']:
            return None
        user['username'] = row['username']
        user['country'] = row['country']
        user['firstname'] = row['firstname']
        user['lastname'] = row['lastname']
        user['groups'] = row['remainingGroups']
        user['domain'] = row['domain']
        user['type'] = 'federatedID'
        return user

    def get_mapped_groups(self, yml_file):
        """
        extracts all mapped LDAP groups from user-sync-config.yml file
        returns: set of LDAP mapped group names
        """
        with open(yml_file) as f:
            elements = yaml.full_load(f)
            group_mapping = elements['directory_users']['groups']
            mapped_groups = set()
            for el in group_mapping:
                mapped_groups.add(el['directory_group'].lower())
        self.logger.debug('LDAP mapped groups from config file: {}'.format(mapped_groups))
        return mapped_groups

    def manage_events(self, events_file, mapped_groups):
        """
        based on the event in the extract, contains the logic to add or not
        the account further in the push list to be used for UST
        it will store the accounts to be added and the ones that get the
        disabled event into 2 separate dict objects self.disabled_accounts and
        self.push_list
        """
        self.logger.debug('start listing AD events')
        with open(events_file) as f:
            # pick event from the bottom up
            csv_r = reversed(list(csv.DictReader(f, delimiter=',')))
            for row in csv_r:
                self.logger.debug('event: {}, user: {}, memberOf: {}'
                    .format(row['eventID'], row['email'], row['remainingGroups']))
                user = self.user_init(row)
                d_key = user['email'].lower()
                # filter out non-email accounts
                if not user:
                    self.logger.debug('skipping: account with no email value')
                    continue
                if user['groups']:
                    memberOf = set(user['groups'].lower().split(','))
                else:
                    memberOf = set()
                # disabled account event
                if row['eventID'] == '4725':
                    self.logger.debug('account disabled event will be managed last')
                    self.disabled_accounts[d_key] = user
                    continue
                # account re-enabled
                elif row['eventID'] == '4722':
                    self.logger.debug('is an account enabled event')
                    if d_key in self.disabled_accounts.keys():
                        del self.disabled_accounts[d_key]
                    # check if it is still memeber of mapped LDAP groups upon enabling
                    if not user['groups'] or not (memberOf & mapped_groups):
                        self.logger.debug('skipping: no mapped group(s) membership')
                        continue
                # group add event
                elif row['eventID'] in ['4728', '4756']:
                    self.logger.debug('is an add to group event')
                    if not (memberOf & mapped_groups):
                        self.logger.debug('skipping: not a mapped group')
                        continue
                # remove from group event (4729)
                else:
                    self.logger.debug('is a remove from group event')
                    if row['removedGroup'].lower() not in mapped_groups:
                        self.logger.debug('skipping: not a mapped group')
                        continue
                # add filtered users to push list & skip disabled accounts from adding
                # to push list if 4728/9 event happens (add to group) while disabled
                if row['enabled'] == 'True':
                    self.logger.info('adding {} to push list'.format(d_key))
                    self.push_list[d_key] = user
                else:
                    # in case 4728 and not 4725 in same list for same account
                    if d_key in self.push_list.keys():
                        self.logger.debug('skipping: disabled account ({}) '
                                          'add to group action'.format(d_key))
                        del self.push_list[d_key]

    def manage_disabled(self):
        """
        check if after 4725 - disable account event - it remains member of any 
        groups in LDAP and if remains memeber of any mapped group, add it to 
        push list with no group membership
        """
        self.logger.debug('managing "status: disabled" accounts')
        if not self.disabled_accounts:
            return
        for key,usr in self.disabled_accounts.items():
            if usr['groups']:
                memberOf = set(usr['groups'].lower().split(','))
            else:
                memberOf = set()
            if memberOf & mapped_groups:
                # still a member so needs removed from all mapped Admin Console groups
                usr['groups'] = ''
                self.logger.info('adding {} for mapped group(s) membership removal'
                                   .format(key))
                self.push_list[usr['email'].lower()] = usr
            else:
                self.logger.debug('skipping {} - no mapped group(s) membership'
                                   .format(key))
        self.logger.info('Finished. Preparing UST csv push list...')

    def create_UST_input(self, out_file):
        """
        creates the standard csv file input for any UST version
        that can be used further for 'push' strategy
        """
        cols = ['firstname',
                'lastname',
                'email',
                'country',
                'groups',
                'type',
                'username', 
                'domain']
        try:
            with open(out_file, 'a+') as csvfile:
                writer = csv.DictWriter(csvfile, fieldnames=cols)
                writer.writeheader()
                for k,v in self.push_list.items():
                    self.logger.debug('PUSH: {}; GROUP(s): {}'
                        .format(k,v['groups']))
                    writer.writerow(v)
        except Exception as e:
            self.logger.critical('Could not save to file: {}'.format(e))
        self.logger.info('-----------finished-----------')


if __name__ == '__main__':
    logger.setLevel(logging.DEBUG)
    fh = logging.FileHandler(LOGS_FOLDER + LOG_FILE_NAME)
    fh.setLevel(logging.DEBUG)
    ch = logging.StreamHandler()
    ch.setLevel(logging.DEBUG)
    formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s',
                                  '%Y-%m-%d %H:%M:%S')
    fh.setFormatter(formatter)
    ch.setFormatter(formatter)
    logger.addHandler(fh)
    logger.addHandler(ch)
    u_push = UMAPI_PUSH()
    mapped_groups = u_push.get_mapped_groups(UST_FILE_PATH)
    u_push.manage_events(EVENTS_FILE_PATH, mapped_groups)
    u_push.manage_disabled()
    u_push.create_UST_input(PUSH_FILE_PATH)

