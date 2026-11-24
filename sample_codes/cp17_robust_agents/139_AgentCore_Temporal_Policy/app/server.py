"""Stateless demo tools. Authorization and sequencing are enforced by Gateway."""
from fastmcp import FastMCP
from pydantic import BaseModel

INQUIRIES = {
    "T001": "商品が届きません。配送状況を確認してください。",
    "T002": "商品の交換を希望します。",
    "T003": "領収書の発行方法を教えてください。",
}
mcp = FastMCP("Temporal inquiries")


class Inquiry(BaseModel):
    ticket_id: str
    text: str


class CloseResult(BaseModel):
    ticket_id: str
    status: str
    simulated: bool


@mcp.tool()
def get_inquiry(ticket_id: str) -> Inquiry:
    """Get inquiry details for T001, T002 or T003 before closing the inquiry."""
    if ticket_id not in INQUIRIES:
        raise ValueError("Inquiry not found")
    return Inquiry(ticket_id=ticket_id, text=INQUIRIES[ticket_id])


@mcp.tool()
def close_inquiry(ticket_id: str) -> CloseResult:
    """Simulate closing an inquiry. No database is changed. Gateway checks authorization."""
    if ticket_id not in INQUIRIES:
        raise ValueError("Inquiry not found")
    return CloseResult(ticket_id=ticket_id, status="closed", simulated=True)


if __name__ == "__main__":
    mcp.run(transport="http", host="0.0.0.0", port=8000, path="/mcp", stateless_http=True)
