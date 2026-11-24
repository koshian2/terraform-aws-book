"""Return original inquiry data. Masking belongs to the Gateway interceptor."""
from fastmcp import FastMCP
from pydantic import BaseModel

INQUIRIES = {
    "T001": "商品が届きません。連絡先は tanaka@example.com です。",
    "T002": "商品の交換を希望します。連絡先は suzuki@example.com です。",
    "T003": "領収書の発行方法を教えてください。",
}

mcp = FastMCP("Inquiries")


class InquiryResult(BaseModel):
    ticket_id: str
    text: str


@mcp.tool()
def get_inquiry(ticket_id: str) -> InquiryResult:
    """Get an inquiry by ID (T001, T002, or T003). 問い合わせIDから内容を取得する。"""
    if ticket_id not in INQUIRIES:
        raise ValueError("Inquiry not found")
    return InquiryResult(ticket_id=ticket_id, text=INQUIRIES[ticket_id])


if __name__ == "__main__":
    mcp.run(transport="http", host="0.0.0.0", port=8000, path="/mcp", stateless_http=True)
