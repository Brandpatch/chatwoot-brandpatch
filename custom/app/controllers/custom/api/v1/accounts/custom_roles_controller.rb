class Custom::Api::V1::Accounts::CustomRolesController < Api::V1::Accounts::BaseController
  before_action :ensure_custom_roles_feature_enabled
  before_action :fetch_custom_role, only: [:show, :update, :destroy]
  before_action :check_authorization

  def index
    @custom_roles = Current.account.brandpatch_custom_roles
  end

  def show; end

  def create
    @custom_role = Current.account.brandpatch_custom_roles.create!(permitted_params)
  end

  def update
    @custom_role.update!(permitted_params)
  end

  def destroy
    @custom_role.destroy!
    head :ok
  end

  private

  def permitted_params
    params.require(:custom_role).permit(:name, :description, permissions: [])
  end

  # [brandpatch] Scoped through Current.account.brandpatch_custom_roles, never
  # Custom::CustomRole.find(...) directly — this is what keeps a Custom Role
  # from one account being reachable by an admin of a different account.
  def fetch_custom_role
    @custom_role = Current.account.brandpatch_custom_roles.find_by(id: params[:id])
  end

  def ensure_custom_roles_feature_enabled
    raise Pundit::NotAuthorizedError unless Current.account.feature_enabled?('custom_roles_brandpatch')
  end

  # [brandpatch] check_authorization's default (controller_name.classify.constantize)
  # would resolve to the unnamespaced, Enterprise-licensed CustomRole class.
  # Pass ours explicitly for every action — matches the EE reference, which
  # also authorizes at the class level uniformly (Custom::CustomRolePolicy
  # only ever checks administrator?, not the specific record, so this has no
  # practical effect beyond staying correctly namespaced).
  def check_authorization
    super(Custom::CustomRole)
  end
end
