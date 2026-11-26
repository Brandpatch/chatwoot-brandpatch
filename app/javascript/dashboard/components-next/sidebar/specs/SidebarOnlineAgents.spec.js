import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import SidebarOnlineAgents from '../SidebarOnlineAgents.vue';

const STORAGE_KEY = 'brandpatch.sidebar.onlineAgents.folded';
const agents = ref([]);
const dispatch = vi.fn();

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useMapGetter: () => agents,
}));

const mountPanel = props =>
  mount(SidebarOnlineAgents, {
    props,
    global: { stubs: { Avatar: true, Icon: true } },
  });

const itemNames = wrapper =>
  wrapper
    .findAll('[data-test-id="online-agents-item"]')
    .map(item => item.text());

describe('SidebarOnlineAgents', () => {
  beforeEach(() => {
    let store = {};
    Object.defineProperty(window, 'localStorage', {
      value: {
        getItem: key => store[key] ?? null,
        setItem: (key, value) => {
          store[key] = String(value);
        },
        clear: () => {
          store = {};
        },
      },
      configurable: true,
    });
    dispatch.mockClear();
    agents.value = [
      { id: 1, name: 'Zoe', availability_status: 'online' },
      { id: 2, name: 'Bruno', availability_status: 'busy' },
      { id: 3, name: 'Carla', availability_status: 'offline' },
      {
        id: 4,
        name: 'ana',
        available_name: 'Ana',
        availability_status: 'online',
      },
      { id: 5, name: 'Ale', availability_status: 'busy' },
    ];
  });

  it('loads the agents on mount', () => {
    mountPanel();
    expect(dispatch).toHaveBeenCalledWith('agents/get');
  });

  it('lists online agents first, then busy, alphabetically, hiding offline', () => {
    const wrapper = mountPanel();

    expect(itemNames(wrapper)).toEqual(['Ana', 'Zoe', 'Ale', 'Bruno']);
    expect(wrapper.find('[data-test-id="online-agents-count"]').text()).toBe(
      '4'
    );
  });

  it('reacts to presence updates in the store', async () => {
    const wrapper = mountPanel();
    agents.value[0].availability_status = 'offline';
    await wrapper.vm.$nextTick();

    expect(itemNames(wrapper)).toEqual(['Ana', 'Ale', 'Bruno']);
  });

  it('shows the empty state when nobody is online', () => {
    agents.value = [{ id: 3, name: 'Carla', availability_status: 'offline' }];
    const wrapper = mountPanel();

    expect(wrapper.find('[data-test-id="online-agents-empty"]').exists()).toBe(
      true
    );
    expect(wrapper.find('[data-test-id="online-agents-count"]').text()).toBe(
      '0'
    );
  });

  it('renders only the count with names in the title when collapsed', () => {
    const wrapper = mountPanel({ isCollapsed: true });
    const compact = wrapper.find('[data-test-id="online-agents-collapsed"]');

    expect(compact.text()).toBe('4');
    expect(compact.attributes('title').split('\n').slice(1)).toEqual([
      'Ana',
      'Zoe',
      'Ale',
      'Bruno',
    ]);
    expect(wrapper.find('[data-test-id="online-agents-item"]').exists()).toBe(
      false
    );
  });

  it('folds the list and persists the folded state', async () => {
    const wrapper = mountPanel();
    await wrapper
      .find('[data-test-id="online-agents-toggle"]')
      .trigger('click');

    expect(wrapper.find('[data-test-id="online-agents-item"]').exists()).toBe(
      false
    );
    expect(window.localStorage.getItem(STORAGE_KEY)).toBe('true');

    const remounted = mountPanel();
    expect(remounted.find('[data-test-id="online-agents-item"]').exists()).toBe(
      false
    );
  });
});
