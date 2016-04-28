# server.rb
require 'sinatra'
require 'sinatra/reloader' if development?
require "sinatra/namespace"
require 'mongoid'

# DB Setup
Mongoid.load! "mongoid.config"

# Models
class Book
  include Mongoid::Document

  field :title, type: String
  field :author, type: String
  field :isbn, type: String

  validates :title, presence: true
  validates :author, presence: true
  validates :isbn, presence: true

  index({ title: 'text' })
  index({ isbn: 1 }, { unique: true, name: "isbn_index" })

  scope :title, -> (title) { where(title: /^#{title}/) }
  scope :isbn, -> (isbn) { where(isbn: isbn) }
  scope :author, -> (author) { where(author: author) }
end

# Serializers
class BookSerializer

  def initialize(book)
    @book = book
  end

  def as_json(*)
    data = {
      id: @book.id.to_s,
      title: @book.title,
      author: @book.author,
      isbn: @book.isbn
    }
    data[:errors] = @book.errors if @book.errors.any?
    data
  end

end

# Endpoints
get '/' do
  'Welcome to BookList!'
end

namespace '/api/v1' do

  before do
    content_type 'application/json'
  end

  helpers do
    def base_url
      @base_url ||= "#{request.env['rack.url_scheme']}://#{request.env['HTTP_HOST']}"
    end

    def json_params
      begin
        JSON.parse(request.body.read)
      rescue
        halt 400, { message: 'Invalid JSON' }.to_json
      end
    end

    def book
      @book ||= Book.where(id: params[:id]).first
    end

    def halt_if_not_found!
      halt(404, { message: 'Book Not Found'}.to_json) unless book
    end

    def serialize(book)
      BookSerializer.new(book).to_json
    end
  end

  get '/books' do
    books = Book.all

    %i(title isbn author).each do |filter|
      books = books.send(filter, params[filter]) if params[filter]
    end

    books.map { |book| BookSerializer.new(book) }.to_json
  end

  get '/books/:id' do |id|
    halt_if_not_found!
    serialize(book)
  end

  post '/books' do
    book = Book.new(json_params)
    halt 422, serialize(book) unless book.save
    response.headers['Location'] = "#{base_url}/api/v1/books/#{book.id}"
    status 201
  end

  patch '/books/:id' do |id|
    halt_if_not_found!
    halt 422, serialize(book) unless book.update_attributes(json_params)
    serialize(book)
  end

  delete '/books/:id' do |id|
    halt_if_not_found!
    book.destroy if book
    status 204
  end

end
