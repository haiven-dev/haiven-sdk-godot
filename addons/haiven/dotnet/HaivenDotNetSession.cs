using System;
using Godot;
using Haiven.Sdk;

namespace Haiven.Sdk.Godot
{
    /// <summary>
    /// Godot scene-tree adapter for the shared C# session core.
    ///
    /// The protocol state machine is the same netstandard2.1 core used by Unity;
    /// this node only supplies WebSocketPeer and Godot's frame-driven polling.
    /// </summary>
    [GlobalClass]
    public partial class HaivenDotNetSession : Node
    {
        private GodotWebSocket? transport;

        [Signal]
        public delegate void RawFrameReceivedEventHandler(string json);

        [Signal]
        public delegate void RawReplyReceivedEventHandler(string json);

        [Signal]
        public delegate void RawEventReceivedEventHandler(string json);

        [Signal]
        public delegate void AuthenticatedEventHandler();

        [Signal]
        public delegate void ExpiredEventHandler();

        [Signal]
        public delegate void ClosedEventHandler(long code, string reason);

        public HaivenSessionCore? Core { get; private set; }

        /// <summary>
        /// Binds this node to a token owner. Call from the Godot main thread
        /// before ConnectToUrl; the delegate is read again for every re-auth.
        /// </summary>
        public void Initialize(
            Func<string> tokenSource,
            Func<string>? nextRequestId = null,
            WebSocketPeer? peer = null)
        {
            Core?.Dispose();
            transport = new GodotWebSocket(peer);
            Core = new HaivenSessionCore(transport, tokenSource, nextRequestId);

            transport.Opened += Core.Opened;
            Core.FrameReceived += received => EmitSignal(SignalName.RawFrameReceived, received.Json);
            Core.ReplyReceived += received => EmitSignal(SignalName.RawReplyReceived, received.Json);
            Core.EventReceived += received => EmitSignal(SignalName.RawEventReceived, received.Json);
            Core.Authenticated += () => EmitSignal(SignalName.Authenticated);
            Core.Expired += () => EmitSignal(SignalName.Expired);
            Core.Closed += (code, reason) => EmitSignal(SignalName.Closed, code, reason);
        }

        public Error ConnectToUrl(string url)
        {
            return RequireTransport().ConnectToUrl(url);
        }

        public ClientFrame Send(string type, object? payload = null)
        {
            return RequireCore().Send(type, payload);
        }

        public void CloseSession()
        {
            RequireCore().Close();
        }

        public override void _Process(double delta)
        {
            transport?.Poll();
        }

        public override void _ExitTree()
        {
            Core?.Dispose();
            Core = null;
            transport = null;
        }

        private GodotWebSocket RequireTransport()
        {
            return transport ?? throw new InvalidOperationException(
                "haiven: call Initialize before ConnectToUrl");
        }

        private HaivenSessionCore RequireCore()
        {
            return Core ?? throw new InvalidOperationException(
                "haiven: call Initialize before using the session");
        }
    }
}
