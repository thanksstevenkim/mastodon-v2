import api, { getLinks } from '../api';

import {
  importFetchedAccounts,
  importFetchedStatuses,
  importFetchedStatus,
} from './importer';

import { normalize } from 'normalizr';
import { conversationMessagesSchema } from 'mastodon/schemas';
import { FETCH_CONVERSATION_MESSAGES_SUCCESS } from '../constants';

export const fetchConversationMessages = conversationId => async dispatch => {
  const response = await fetch(`/api/v1/conversations/${conversationId}/messages`);
  if (!response.ok) throw new Error('메시지 로드 실패');
  const data = await response.json();
  const { entities, result } = normalize(data, [conversationMessagesSchema]);
  dispatch({
    type: FETCH_CONVERSATION_MESSAGES_SUCCESS,
    payload: { conversationId, messages: entities.messages },
  });
};

export const CONVERSATIONS_MOUNT   = 'CONVERSATIONS_MOUNT';
export const CONVERSATIONS_UNMOUNT = 'CONVERSATIONS_UNMOUNT';

export const CONVERSATIONS_FETCH_REQUEST = 'CONVERSATIONS_FETCH_REQUEST';
export const CONVERSATIONS_FETCH_SUCCESS = 'CONVERSATIONS_FETCH_SUCCESS';
export const CONVERSATIONS_FETCH_FAIL    = 'CONVERSATIONS_FETCH_FAIL';
export const CONVERSATIONS_UPDATE        = 'CONVERSATIONS_UPDATE';

export const CONVERSATIONS_READ = 'CONVERSATIONS_READ';

export const CONVERSATIONS_DELETE_REQUEST = 'CONVERSATIONS_DELETE_REQUEST';
export const CONVERSATIONS_DELETE_SUCCESS = 'CONVERSATIONS_DELETE_SUCCESS';
export const CONVERSATIONS_DELETE_FAIL    = 'CONVERSATIONS_DELETE_FAIL';

export const SEND_MESSAGE_REQUEST = 'SEND_MESSAGE_REQUEST';
export const SEND_MESSAGE_SUCCESS = 'SEND_MESSAGE_SUCCESS';
export const SEND_MESSAGE_FAIL = 'SEND_MESSAGE_FAIL';

export const mountConversations = () => ({
  type: CONVERSATIONS_MOUNT,
});

export const unmountConversations = () => ({
  type: CONVERSATIONS_UNMOUNT,
});

export const markConversationRead = conversationId => (dispatch) => {
  dispatch({
    type: CONVERSATIONS_READ,
    id: conversationId,
  });

  api().post(`/api/v1/conversations/${conversationId}/read`);
};

export const expandConversations = ({ maxId } = {}) => (dispatch, getState) => {
  const state = getState();
  const isLoading = state.getIn(['conversations', 'isLoading']);
  const hasMore = state.getIn(['conversations', 'hasMore']);

  // Don't load more if we're already loading or there's no more data
  if (isLoading || (!hasMore && maxId)) {
    return;
  }

  dispatch(expandConversationsRequest());

  const params = { max_id: maxId, limit: 20 };

  // If loading newer items, use since_id
  if (!maxId) {
    const firstItem = state.getIn(['conversations', 'items', 0]);
    if (firstItem) {
      params.since_id = firstItem.get('last_status');
    }
  }

  const isLoadingRecent = !!params.since_id;

  api().get('/api/v1/conversations', { params })
    .then(response => {
      const next = getLinks(response).refs.find(link => link.rel === 'next');

      // Import accounts and statuses into the store
      dispatch(importFetchedAccounts(response.data.reduce((aggr, item) => aggr.concat(item.accounts), [])));
      dispatch(importFetchedStatuses(response.data.map(item => item.last_status).filter(x => !!x)));
      
      // Update the conversations list
      dispatch(expandConversationsSuccess(response.data, next ? next.uri : null, isLoadingRecent));
    })
    .catch(err => {
      console.error(err);
      dispatch(expandConversationsFail(err));
    });
};

export const expandConversationsRequest = () => ({
  type: CONVERSATIONS_FETCH_REQUEST,
});

export const expandConversationsSuccess = (conversations, next, isLoadingRecent) => ({
  type: CONVERSATIONS_FETCH_SUCCESS,
  conversations,
  next,
  isLoadingRecent,
});

export const expandConversationsFail = error => ({
  type: CONVERSATIONS_FETCH_FAIL,
  error,
});

export const updateConversations = conversation => dispatch => {
  dispatch(importFetchedAccounts(conversation.accounts));

  if (conversation.last_status) {
    dispatch(importFetchedStatus(conversation.last_status));
  }

  dispatch({
    type: CONVERSATIONS_UPDATE,
    conversation,
  });
};

export const deleteConversation = conversationId => (dispatch) => {
  dispatch(deleteConversationRequest(conversationId));

  api().delete(`/api/v1/conversations/${conversationId}`)
    .then(() => dispatch(deleteConversationSuccess(conversationId)))
    .catch(error => dispatch(deleteConversationFail(conversationId, error)));
};

export const deleteConversationRequest = id => ({
  type: CONVERSATIONS_DELETE_REQUEST,
  id,
});

export const deleteConversationSuccess = id => ({
  type: CONVERSATIONS_DELETE_SUCCESS,
  id,
});

export const deleteConversationFail = (id, error) => ({
  type: CONVERSATIONS_DELETE_FAIL,
  id,
  error,
});

export const sendMessage = (conversationId, content) => async dispatch => {
  dispatch({ type: SEND_MESSAGE_REQUEST });

  try {
    const response = await api().post(`/api/v1/conversations/${conversationId}/messages`, {
      content,
    });

    dispatch({
      type: SEND_MESSAGE_SUCCESS,
      payload: { conversationId, message: response.data },
    });

    return response.data;
  } catch (error) {
    dispatch({
      type: SEND_MESSAGE_FAIL,
      error,
    });
    throw error;
  }
};
