from fastmcp import FastMCP
import httpx
import json
from starlette.responses import JSONResponse
import uvicorn

# FastMCP server configuration
mcp = FastMCP("bankofcanada-exchangerates")

async def getExchangeRate(currencyCode: str):

    #get rates from Bank Of Canada API
    r = httpx.get("https://bcd-api-dca-ipa.cbsa-asfc.cloud-nuage.canada.ca/exchange-rate-lambda/exchange-rates")
    rates = json.loads(r.text)["ForeignExchangeRates"]
    
    # find rate using FromCurrency field
    for rate in rates:
        if rate["FromCurrency"]["Value"] == currencyCode:
            return float(rate['Rate'])

    return None

@mcp.tool()
async def convertToCanadianDollars(amount: float, currencyCode: str):
    """
    converts a given amount of Canadian currency to a target currency

    Args:
        amount: The amount of Canadian currency to be converted to the target currency (e.g. 500.23)
        currencyCode: The ISO 4217 currency code for the target currency (e.g. "USD")
    
    Returns:
        target currency amount
    """
    rate = await getExchangeRate(currencyCode)
    convertedAmount = amount / rate
    return round(convertedAmount, 2)

@mcp.tool()
async def listCurrencies():
    """
    Lists all foreign currencies available for conversion in ISO 4217 currency code format
    
    Returns:
        foreign currency codes list
    """
    r = httpx.get("https://bcd-api-dca-ipa.cbsa-asfc.cloud-nuage.canada.ca/exchange-rate-lambda/exchange-rates")
    rates = json.loads(r.text)["ForeignExchangeRates"]
    currencies = [x['FromCurrency']['Value'] for x in rates] 
    return sorted(currencies)


# Add health check endpoint for Azure Container Apps
@mcp.custom_route("/health", methods=["GET"])
async def health_check(request):
    return JSONResponse({"status": "healthy", "service": "mcp-server"})


# Create a Starlette ASGI web application for uvicorn to serve
app = mcp.http_app()

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)