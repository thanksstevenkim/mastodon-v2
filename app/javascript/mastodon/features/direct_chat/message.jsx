import React from 'react';

const Message = ({ message, isMine }) => (
  <div className={`message flex my-2 ${isMine ? 'justify-end' : 'justify-start'}`}>  
    <div
      className={`bubble px-4 py-2 rounded-lg max-w-2/3 ${
        isMine ? 'bg-yellow-300 text-black' : 'bg-gray-100 text-gray-900'
      }`}>
      <div
        className="message-content"
        dangerouslySetInnerHTML={{
          __html: message.content_html || message.content,
        }}
      />
    </div>
    <span className="timestamp text-xs text-gray-500 ml-2 self-end">
      {new Date(message.created_at).toLocaleTimeString()}
    </span>
  </div>
);

export default Message;