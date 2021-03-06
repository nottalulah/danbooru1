require File.dirname(__FILE__) + '/../test_helper'

# There's a bug where setup isn't called in functional tests
ActionMailer::Base.delivery_method = :test
ActionMailer::Base.perform_deliveries = true
ActionMailer::Base.deliveries = []

class DmailControllerTest < ActionController::TestCase
  fixtures :users
  
  def create_dmail(to_id, from_id, message, params = {})
    Dmail.create({:to_id => to_id, :from_id => from_id, :title => message, :body => message}.merge(params))
  end
  
  def test_create
    get :compose, {}, {:user_id => 1}
    assert_response :success
    
    post :create, {:dmail => {:to_name => "member", :title => "max", :body => "max"}}, {:user_id => 1}
    dmail = Dmail.find_by_from_id(1)
    assert_not_nil(dmail)
    assert_equal("max", dmail.title)
    assert_equal(4, dmail.to_id)
  end
  
  def test_inbox
    create_dmail(1, 2, "hey")
    create_dmail(2, 1, "mox")
    create_dmail(1, 3, "lox")
    create_dmail(1, 4, "hoge")
    
    get :inbox, {}, {:user_id => 1}
    assert_response :success
  end
  
  def test_show
    d1 = create_dmail(1, 2, "hey")
    d2 = create_dmail(2, 1, "mox")
    d3 = create_dmail(1, 3, "lox")
    d4 = create_dmail(2, 4, "hoge")
    
    get :show, {:id => d1.id}, {:user_id => 1}
    assert_response :success
    
    get :show, {:id => d4.id}, {:user_id => 1}
    assert_redirected_to :controller => "user", :action => "login"
  end
end
