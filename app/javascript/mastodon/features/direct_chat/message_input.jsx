import React, { useState } from 'react';
import { useDispatch } from 'react-redux';
import { sendMessage } from 'mastodon/actions/conversations';

const MessageInput = ({ conversationId, className }) => {
  const [text, setText] = useState('');
  const [sending, setSending] = useState(false);
  const dispatch = useDispatch();

  const handleSend = async () => {
    if (!text.trim() || sending) return;
    
    setSending(true);
    try {
      await dispatch(sendMessage(conversationId, text));
      setText('');
    } catch (error) {
      console.error('Failed to send message:', error);
    } finally {
      setSending(false);
    }
  };

  return (
    <div className={className}>      <textarea
        className="w-full p-2 border rounded-md resize-none"
        rows={2}
        placeholder="메시지를 입력하세요... (Enter: 전송, Shift+Enter: 줄바꿈)"
        value={text}
        onChange={e => setText(e.target.value)}
        onKeyDown={e => {
          if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            handleSend();
          }
        }}
      /><button
        className="mt-2 px-4 py-1 rounded bg-yellow-500 text-white disabled:opacity-50"
        onClick={handleSend}
        disabled={!text.trim() || sending}
      >
        {sending ? '전송중...' : '전송'}
      </button>
    </div>
  );
};

export default MessageInput;