import React from 'react';
import { useSelector } from 'react-redux';
import Message from './message';

const MessageList = ({ conversationId, className }) => {
  const messages = useSelector(state =>
    state.getIn(['conversations', 'messages', conversationId], [])
  ).toJS();
  const currentUser = useSelector(state =>
    state.getIn(['session', 'currentUser']).toJS()
  );

  return (
    <div className={className}>
      {messages.map(msg => (
        <Message
          key={msg.id}
          message={msg}
          isMine={msg.account.id === currentUser.id}
        />
      ))}
    </div>
  );
};

export default MessageList;