class Podbay::Components::Daemon
  class Iptables
    class << self
      def table(name)
        _instance.table(name)
      end

      def chain(name)
        _instance.chain(name)
      end

      def mock(mock)
        @_instance = mock
        yield
      ensure
        @_instance = nil
      end

      private

      def _instance
        @_instance ||= new { |r| system("iptables #{r}") }
      end
    end # Class Methods

    attr_reader :block

    def initialize(&block)
      @block = block
    end

    def table(name)
      Table.new(name, &block)
    end

    def chain(name)
      table('filter').chain(name)
    end

    class Table
      attr_reader :name
      attr_reader :block

      def initialize(name, &block)
        @name = name.downcase
        @block = block
      end

      def chain(name)
        Chain.new(self, name)
      end

      def run(desc)
        block.call("-t #{name} #{desc}")
      end
    end # Table

    class Chain
      attr_reader :table
      attr_reader :name

      def initialize(table, name)
        @table = table
        @name = name.upcase
      end

      def rule(desc)
        Rule.new(self, desc)
      end

      def append_rule(desc)
        table.run("-A #{name} #{desc}")
      end

      def insert_rule(desc, index = nil)
        index &&= " #{index}" # Prepend a space if it's defined
        table.run("-I #{name}#{index} #{desc}")
      end

      def rule_exists?(desc)
        table.run("-C #{name} #{desc}")
      end

      def delete_rule(desc)
        table.run("-D #{name} #{desc}")
      end

      def create
        table.run("-N #{name}") or fail "could not create chain #{name}"
      end

      def exists?
        table.run("-L #{name} -n")
      end

      def flush
        table.run("-F #{name}") or fail "could not flush chain #{name}"
      end

      def delete
        table.run("-X #{name}") or fail "could not delete chain #{name}"
      end

      def policy(target)
        table.run("-P #{name} #{target}")
      end

      def create_or_flush
        exists? && flush || create
      end

      def create_if_needed
        exists? || create
      end
    end # Chain

    class Rule
      attr_reader :chain
      attr_reader :desc

      def initialize(chain, desc)
        @chain = chain
        @desc = desc
      end

      def append
        chain.append_rule(desc) or
          fail "could not append onto #{chain.name}: #{desc}"
      end

      def append_if_needed
        exists? || append
      end

      def insert(index = nil)
        chain.insert_rule(desc, index) or
          fail "could not insert into #{chain.name}: #{desc}"
      end

      def insert_if_needed(index = nil)
        exists? || insert(index)
      end

      def exists?
        chain.rule_exists?(desc)
      end

      def delete
        chain.delete_rule(desc) or
          fail "could not delete from #{chain.name}: #{desc}"
      end
    end
  end
end
