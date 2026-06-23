require "../spec_helper"
require "openapi/form/serializable"
require "openapi/macro/enum"

# Mirrors the Stripe POST /v1/checkout/sessions request body (simplified).
#
# The equivalent curl call:
#   curl https://api.stripe.com/v1/checkout/sessions \
#     -d success_url="https://example.com/success" \
#     -d cancel_url="https://example.com/cancel" \
#     -d "payment_method_types[]=card" \
#     -d "line_items[][name]=T-shirt" \
#     -d "line_items[][description]=Comfortable cotton t-shirt" \
#     -d "line_items[][amount]=1500" \
#     -d "line_items[][currency]=usd" \
#     -d "line_items[][quantity]=2"
#
# Our serializer uses explicit indices (`line_items[0][name]` rather than
# `line_items[][name]`) which Stripe's Rack-based server accepts equivalently.

openapi_enum CheckoutPaymentMethodType do
  Card   = "card"
  Alipay = "alipay"
  Klarna = "klarna"
end

struct CheckoutLineItem
  include OpenAPI::Form::Serializable

  getter name : String
  getter amount : Int32
  getter currency : String
  getter description : String?
  getter quantity : Int32?

  def initialize(@name, @amount, @currency, @description = nil, @quantity = nil)
  end
end

struct CheckoutSessionRequest
  include OpenAPI::Form::Serializable

  getter success_url : String
  getter cancel_url : String
  getter payment_method_types : Array(CheckoutPaymentMethodType)?
  getter line_items : Array(CheckoutLineItem)?

  def initialize(@success_url, @cancel_url, @payment_method_types = nil, @line_items = nil)
  end
end

describe "Stripe checkout session form encoding" do
  it "encodes scalar fields" do
    req = CheckoutSessionRequest.new(
      success_url: "https://example.com/success",
      cancel_url: "https://example.com/cancel"
    )
    params = HTTP::Params.parse(req.to_form_params)
    params["success_url"].should eq("https://example.com/success")
    params["cancel_url"].should eq("https://example.com/cancel")
  end

  it "encodes payment_method_types enum array with wire values (card, not Card)" do
    req = CheckoutSessionRequest.new(
      success_url: "https://example.com/success",
      cancel_url: "https://example.com/cancel",
      payment_method_types: [CheckoutPaymentMethodType::Card]
    )
    params = HTTP::Params.parse(req.to_form_params)
    params.fetch_all("payment_method_types[]").should eq(["card"])
  end

  it "encodes a single line item with indexed bracket notation" do
    req = CheckoutSessionRequest.new(
      success_url: "https://example.com/success",
      cancel_url: "https://example.com/cancel",
      line_items: [
        CheckoutLineItem.new(
          name: "T-shirt",
          amount: 1500,
          currency: "usd",
          description: "Comfortable cotton t-shirt",
          quantity: 2
        ),
      ]
    )
    params = HTTP::Params.parse(req.to_form_params)
    params["line_items[0][name]"].should eq("T-shirt")
    params["line_items[0][description]"].should eq("Comfortable cotton t-shirt")
    params["line_items[0][amount]"].should eq("1500")
    params["line_items[0][currency]"].should eq("usd")
    params["line_items[0][quantity]"].should eq("2")
  end

  it "encodes multiple line items with separate indices" do
    req = CheckoutSessionRequest.new(
      success_url: "https://example.com/success",
      cancel_url: "https://example.com/cancel",
      line_items: [
        CheckoutLineItem.new(name: "T-shirt", amount: 1500, currency: "usd"),
        CheckoutLineItem.new(name: "Mug", amount: 800, currency: "usd"),
      ]
    )
    params = HTTP::Params.parse(req.to_form_params)
    params["line_items[0][name]"].should eq("T-shirt")
    params["line_items[0][amount]"].should eq("1500")
    params["line_items[1][name]"].should eq("Mug")
    params["line_items[1][amount]"].should eq("800")
  end

  it "omits nil optional fields from line items" do
    req = CheckoutSessionRequest.new(
      success_url: "https://example.com/success",
      cancel_url: "https://example.com/cancel",
      line_items: [CheckoutLineItem.new(name: "T-shirt", amount: 1500, currency: "usd")]
    )
    encoded = req.to_form_params
    encoded.should_not contain("description")
    encoded.should_not contain("quantity")
  end

  it "produces the full curl-equivalent form body" do
    req = CheckoutSessionRequest.new(
      success_url: "https://example.com/success",
      cancel_url: "https://example.com/cancel",
      payment_method_types: [CheckoutPaymentMethodType::Card],
      line_items: [
        CheckoutLineItem.new(
          name: "T-shirt",
          amount: 1500,
          currency: "usd",
          description: "Comfortable cotton t-shirt",
          quantity: 2
        ),
      ]
    )
    params = HTTP::Params.parse(req.to_form_params)
    params["success_url"].should eq("https://example.com/success")
    params["cancel_url"].should eq("https://example.com/cancel")
    params.fetch_all("payment_method_types[]").should eq(["card"])
    params["line_items[0][name]"].should eq("T-shirt")
    params["line_items[0][description]"].should eq("Comfortable cotton t-shirt")
    params["line_items[0][amount]"].should eq("1500")
    params["line_items[0][currency]"].should eq("usd")
    params["line_items[0][quantity]"].should eq("2")
  end
end
