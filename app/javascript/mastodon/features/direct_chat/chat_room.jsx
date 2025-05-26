import React, { useEffect } from 'react';
import { useParams } from 'react-router-dom';
import { useSelector, useDispatch } from 'react-redux';
import MessageList from './message_list';
import MessageInput from './message_input';
import { fetchConversationMessages } from 'mastodon/actions/conversations';

const ChatRoom = () => {
  const { conversationId } = useParams();
  const dispatch = useDispatch();

  // 대화방 메시지 로드
  useEffect(() => {
    dispatch(fetchConversationMessages(conversationId));
  }, [dispatch, conversationId]);

  const conversation = useSelector(state =>
    state.getIn(['conversations', 'items']).find(c => c.get('id') === conversationId)
  );
  const recipient = conversation?.get('accounts').first();

  return (
    <div className="chat-room flex flex-col h-full">
      <header className="chat-header flex items-center justify-between p-4 border-b">
        <h2 className="text-lg font-semibold">
          {recipient?.get('display_name') || recipient?.get('acct')}
        </h2>
      </header>

      <MessageList
        conversationId={conversationId}
        className="flex-1 overflow-y-auto p-4"
      />

      <MessageInput
        conversationId={conversationId}
        className="p-4 border-t"
      />
    </div>
  );
};

export default ChatRoom;