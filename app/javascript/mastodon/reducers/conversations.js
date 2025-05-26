import { Map as ImmutableMap, List as ImmutableList } from 'immutable';

import { blockAccountSuccess, muteAccountSuccess } from 'mastodon/actions/accounts';
import { blockDomainSuccess } from 'mastodon/actions/domain_blocks';
import { FETCH_CONVERSATION_MESSAGES_SUCCESS } from '../constants';

import {
  CONVERSATIONS_MOUNT,
  CONVERSATIONS_UNMOUNT,
  CONVERSATIONS_FETCH_REQUEST,
  CONVERSATIONS_FETCH_SUCCESS,
  CONVERSATIONS_FETCH_FAIL,
  CONVERSATIONS_UPDATE,
  CONVERSATIONS_READ,
  CONVERSATIONS_DELETE_SUCCESS,
  SEND_MESSAGE_SUCCESS,
} from '../actions/conversations';
import { compareId } from '../compare_id';

const initialState = ImmutableMap({
  items: ImmutableList(),
  messages: ImmutableMap(),
  isLoading: false,
  hasMore: true,
  mounted: false,
});

const conversationToMap = item => ImmutableMap({
  id: item.id,
  unread: item.unread,
  accounts: ImmutableList(item.accounts.map(a => a.id)),
  last_status: item.last_status ? item.last_status.id : null,
});

const updateConversation = (state, item) => state.update('items', list => {
  const index   = list.findIndex(x => x.get('id') === item.id);
  const newItem = conversationToMap(item);

  if (index === -1) {
    return list.unshift(newItem);
  } else {
    return list.set(index, newItem);
  }
});

const expandNormalizedConversations = (state, conversations, next, isLoadingRecent) => {
  let items = ImmutableList(conversations.map(conversationToMap));

  return state.withMutations(mutable => {
    if (!items.isEmpty()) {
      mutable.update('items', list => {
        // If loading recent items, add them at the beginning
        if (isLoadingRecent) {
          const newIds = items.map(item => item.get('id'));
          list = list.filterNot(item => newIds.includes(item.get('id')));
          list = items.concat(list);
        } else {
          // If loading older items, merge with existing
          list = list.map(oldItem => {
            const newItemIndex = items.findIndex(x => x.get('id') === oldItem.get('id'));
            if (newItemIndex === -1) {
              return oldItem;
            }
            const newItem = items.get(newItemIndex);
            items = items.delete(newItemIndex);
            return newItem;
          });

          list = list.concat(items);
        }

        // Sort by last_status id to maintain chronological order
        return list.sortBy(x => x.get('last_status'), (a, b) => {
          if(a === null || b === null) {
            return -1;
          }
          return compareId(a, b) * -1;
        });
      });
    }

    // Update hasMore flag based on presence of next page
    if (!next && !isLoadingRecent) {
      mutable.set('hasMore', false);
    }

    mutable.set('isLoading', false);
  });
};

const filterConversations = (state, accountIds) => {
  return state.update('items', list => list.filterNot(item => item.get('accounts').some(accountId => accountIds.includes(accountId))));
};

export default function conversations(state = initialState, action) {
  switch (action.type) {
  case FETCH_CONVERSATION_MESSAGES_SUCCESS:
    return state.setIn(['messages', action.payload.conversationId], ImmutableMap(action.payload.messages));
  case SEND_MESSAGE_SUCCESS:
    return state.updateIn(
      ['messages', action.payload.conversationId],
      ImmutableMap(),
      messages => messages.set(action.payload.message.id, action.payload.message)
    );
  case CONVERSATIONS_FETCH_REQUEST:
    return state.set('isLoading', true);
  case CONVERSATIONS_FETCH_FAIL:
    return state.set('isLoading', false);
  case CONVERSATIONS_FETCH_SUCCESS:
    return expandNormalizedConversations(state, action.conversations, action.next, action.isLoadingRecent);
  case CONVERSATIONS_UPDATE:
    return updateConversation(state, action.conversation);
  case CONVERSATIONS_MOUNT:
    return state.update('mounted', count => count + 1);
  case CONVERSATIONS_UNMOUNT:
    return state.update('mounted', count => count - 1);
  case CONVERSATIONS_READ:
    return state.update('items', list => list.map(item => {
      if (item.get('id') === action.id) {
        return item.set('unread', false);
      }

      return item;
    }));
  case blockAccountSuccess.type:
  case muteAccountSuccess.type:
    return filterConversations(state, [action.payload.relationship.id]);
  case blockDomainSuccess.type:
    return filterConversations(state, action.payload.accounts);
  case CONVERSATIONS_DELETE_SUCCESS:
    return state.update('items', list => list.filterNot(item => item.get('id') === action.id));
  default:
    return state;
  }
}
